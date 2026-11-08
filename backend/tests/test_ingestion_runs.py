"""Tests for the ingestion schedule, the run lock and the scheduler service.

Runs against the real database inside one outer transaction: the repository's
commits only release savepoints, and everything is rolled back afterwards.
"""

import asyncio
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from typing import Any

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from meinimpact.core.config import Settings
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.pipeline.ingestion import IngestionSummary
from meinimpact.infrastructure.pipeline.run_repository import (
    PostgresIngestionRunRepository,
    Schedule,
)
from meinimpact.services.ingestion_runs import IngestionRuns, Overview, run_scheduler

NOW = datetime(2026, 11, 8, 12, 0, tzinfo=UTC)
STALE = timedelta(hours=3)


@pytest.fixture
async def sessions() -> AsyncGenerator[async_sessionmaker[AsyncSession]]:
    db = Database(Settings().database_url)
    async with db.engine.connect() as connection:
        transaction = await connection.begin()
        factory = async_sessionmaker(
            bind=connection,
            expire_on_commit=False,
            join_transaction_mode="create_savepoint",
        )
        async with factory() as session:
            await session.execute(text("DELETE FROM ingestion_runs"))
            await session.execute(
                text(
                    "UPDATE ingestion_schedule SET enabled = true, interval_hours = 48"
                )
            )
            await session.commit()
        yield factory
        await transaction.rollback()
    await db.close()


@pytest.fixture
async def repo(
    sessions: async_sessionmaker[AsyncSession],
) -> AsyncGenerator[PostgresIngestionRunRepository]:
    async with sessions() as session:
        yield PostgresIngestionRunRepository(session)


async def test_migration_seeds_a_schedule_every_two_days(
    repo: PostgresIngestionRunRepository,
) -> None:
    assert await repo.schedule() == Schedule(enabled=True, interval_hours=48)


async def test_manual_claim_blocks_a_second_run(
    repo: PostgresIngestionRunRepository,
) -> None:
    first = await repo.claim("manual", now=NOW, stale_after=STALE)
    second = await repo.claim("manual", now=NOW, stale_after=STALE)

    assert first is not None
    assert second is None


async def test_finished_run_records_summary_and_frees_the_lock(
    repo: PostgresIngestionRunRepository,
) -> None:
    run_id = await repo.claim("manual", now=NOW, stale_after=STALE)
    assert run_id is not None
    await repo.finish(run_id, now=NOW, summary={"listed": 3}, error=None)

    [run] = await repo.recent()
    assert run.status == "succeeded"
    assert run.summary == {"listed": 3}
    assert await repo.claim("manual", now=NOW, stale_after=STALE) is not None


async def test_failed_run_is_recorded_as_failed(
    repo: PostgresIngestionRunRepository,
) -> None:
    run_id = await repo.claim("manual", now=NOW, stale_after=STALE)
    assert run_id is not None
    await repo.finish(run_id, now=NOW, summary=None, error="boom")

    [run] = await repo.recent()
    assert (run.status, run.error) == ("failed", "boom")


async def test_stale_running_run_is_marked_interrupted(
    repo: PostgresIngestionRunRepository,
) -> None:
    await repo.claim("manual", now=NOW - timedelta(hours=4), stale_after=STALE)

    assert await repo.claim("manual", now=NOW, stale_after=STALE) is not None
    old = (await repo.recent())[1]
    assert old.status == "failed"
    assert old.error is not None and "Unterbrochen" in old.error


async def test_scheduled_claim_waits_for_the_interval(
    repo: PostgresIngestionRunRepository,
) -> None:
    run_id = await repo.claim("scheduled", now=NOW, stale_after=STALE)
    assert run_id is not None  # never ran before: due at once
    await repo.finish(run_id, now=NOW, summary={}, error=None)

    soon = NOW + timedelta(hours=47)
    later = NOW + timedelta(hours=48)
    assert await repo.claim("scheduled", now=soon, stale_after=STALE) is None
    assert await repo.claim("scheduled", now=later, stale_after=STALE) is not None


async def test_manual_run_postpones_the_scheduled_one(
    repo: PostgresIngestionRunRepository,
) -> None:
    run_id = await repo.claim("manual", now=NOW, stale_after=STALE)
    assert run_id is not None
    await repo.finish(run_id, now=NOW, summary={}, error=None)

    next_day = NOW + timedelta(hours=24)
    assert await repo.claim("scheduled", now=next_day, stale_after=STALE) is None


async def test_disabled_schedule_never_claims_but_manual_still_works(
    repo: PostgresIngestionRunRepository,
) -> None:
    await repo.set_schedule(Schedule(enabled=False, interval_hours=24), now=NOW)

    assert await repo.schedule() == Schedule(enabled=False, interval_hours=24)
    assert await repo.claim("scheduled", now=NOW, stale_after=STALE) is None
    assert await repo.claim("manual", now=NOW, stale_after=STALE) is not None


# --- service ----------------------------------------------------------------


def _service(sessions: async_sessionmaker[AsyncSession], ingest: Any) -> IngestionRuns:
    database: Any = SimpleNamespace(session_factory=sessions)
    return IngestionRuns(database, Settings(), ingest=ingest)


async def test_run_if_due_runs_and_records_the_summary(
    sessions: async_sessionmaker[AsyncSession],
) -> None:
    async def ingest(_: Settings) -> IngestionSummary:
        return IngestionSummary(listed=5, errors=["enrich x: y"])

    runs = _service(sessions, ingest)

    assert await runs.run_if_due() is True
    assert await runs.run_if_due() is False  # interval not passed yet
    overview = await runs.overview()
    [run] = overview.runs
    assert run.trigger == "scheduled"
    assert run.status == "succeeded"
    assert run.summary is not None and run.summary["listed"] == 5
    assert overview.running is None


async def test_execute_records_a_crash_instead_of_raising(
    sessions: async_sessionmaker[AsyncSession],
) -> None:
    async def ingest(_: Settings) -> IngestionSummary:
        raise RuntimeError("registry down")

    runs = _service(sessions, ingest)
    run_id = await runs.claim("manual")
    assert run_id is not None

    await runs.execute(run_id)

    [run] = (await runs.overview()).runs
    assert run.status == "failed"
    assert run.error == "RuntimeError: registry down"


async def test_set_schedule_through_the_service(
    sessions: async_sessionmaker[AsyncSession],
) -> None:
    runs = _service(sessions, None)
    await runs.set_schedule(Schedule(enabled=True, interval_hours=72))
    assert (await runs.overview()).schedule.interval_hours == 72


async def test_scheduler_survives_a_failed_check() -> None:
    checks = 0

    class FlakyRuns:
        async def run_if_due(self) -> bool:
            nonlocal checks
            checks += 1
            if checks == 1:
                raise RuntimeError("db hiccup")
            raise asyncio.CancelledError

    with pytest.raises(asyncio.CancelledError):
        await run_scheduler(FlakyRuns(), timedelta(0))  # type: ignore[arg-type]
    assert checks == 2


def test_next_due_follows_the_last_run() -> None:
    schedule = Schedule(enabled=True, interval_hours=48)
    assert Overview(schedule=schedule, runs=[]).next_due is not None
    off = Schedule(enabled=False, interval_hours=48)
    assert Overview(schedule=off, runs=[]).next_due is None
