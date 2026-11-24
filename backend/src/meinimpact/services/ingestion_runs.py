"""Scheduled and manual ingestion runs with a recorded history.

Both the admin page and the scheduler go through `IngestionRuns`: claim a run
in the database (which also keeps two machines from running at once), run the
configured ingestion, record the summary or the error. The scheduler only
asks every few minutes whether a run is due; the interval itself lives in the
database so the admin page can change it without a deploy.
"""

import asyncio
import logging
from collections.abc import Awaitable, Callable
from dataclasses import asdict, dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from meinimpact.core.config import Settings
from meinimpact.infrastructure.alerts import alert
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.pipeline.drift import find_drift
from meinimpact.infrastructure.pipeline.ingestion import IngestionSummary
from meinimpact.infrastructure.pipeline.run_repository import (
    PostgresIngestionRunRepository,
    RunRecord,
    Schedule,
    Trigger,
)
from meinimpact.services.ingestion import run_configured_ingestion

logger = logging.getLogger(__name__)

# A run takes up to ~30 min (OParl alone 15-25); one still "running" after
# this is treated as interrupted and no longer blocks new runs.
STALE_AFTER = timedelta(hours=3)
INTERVAL_CHOICES_HOURS = (12, 24, 48, 72, 168)

Ingest = Callable[[Settings], Awaitable[IngestionSummary]]


@dataclass(frozen=True)
class Overview:
    schedule: Schedule
    runs: list[RunRecord]

    @property
    def running(self) -> RunRecord | None:
        return next((run for run in self.runs if run.status == "running"), None)

    @property
    def next_due(self) -> datetime | None:
        """When the scheduler will next start a run; None if switched off."""
        if not self.schedule.enabled:
            return None
        if not self.runs:
            return datetime.now(UTC)
        return self.runs[0].started_at + timedelta(hours=self.schedule.interval_hours)


class IngestionRuns:
    def __init__(
        self,
        database: Database,
        settings: Settings,
        ingest: Ingest = run_configured_ingestion,
    ) -> None:
        self._database = database
        self._settings = settings
        self._ingest = ingest

    async def overview(self) -> Overview:
        async with self._database.session_factory() as session:
            repository = PostgresIngestionRunRepository(session)
            return Overview(
                schedule=await repository.schedule(), runs=await repository.recent()
            )

    async def set_schedule(self, schedule: Schedule) -> None:
        async with self._database.session_factory() as session:
            await PostgresIngestionRunRepository(session).set_schedule(
                schedule, now=datetime.now(UTC)
            )

    async def claim(self, trigger: Trigger) -> int | None:
        async with self._database.session_factory() as session:
            return await PostgresIngestionRunRepository(session).claim(
                trigger, now=datetime.now(UTC), stale_after=STALE_AFTER
            )

    async def execute(self, run_id: int) -> None:
        """Runs ingestion for a claimed run, records how it ended and raises
        an alert for everything someone should look at."""
        summary: IngestionSummary | None = None
        error: str | None = None
        try:
            summary = await self._ingest(self._settings)
        except Exception as exc:  # recorded for the admin page, never raised
            logger.exception("Ingestion run %s failed", run_id)
            error = f"{type(exc).__name__}: {exc}"
        async with self._database.session_factory() as session:
            repository = PostgresIngestionRunRepository(session)
            stored = asdict(summary) if summary is not None else None
            if summary is not None and stored is not None:
                summary.drift = find_drift(
                    stored["sources"], await self._source_history(repository)
                )
                stored["drift"] = summary.drift
            await repository.finish(
                run_id, now=datetime.now(UTC), summary=stored, error=error
            )
        for problem in _alerts(summary, error):
            alert(problem)
        logger.info("Ingestion run %s finished: %s", run_id, summary or error)

    @staticmethod
    async def _source_history(
        repository: PostgresIngestionRunRepository,
    ) -> list[list[dict[str, Any]]]:
        """Source rows of the latest finished runs, newest first."""
        return [
            list(run.summary.get("sources", []))
            for run in await repository.recent()
            if run.status == "succeeded" and run.summary
        ]

    async def run_if_due(self) -> bool:
        run_id = await self.claim("scheduled")
        if run_id is None:
            return False
        await self.execute(run_id)
        return True


def _alerts(summary: IngestionSummary | None, error: str | None) -> list[str]:
    if summary is None:
        return [f"Ingestion fehlgeschlagen: {error}"]
    problems = [f"Quelle fehlgeschlagen: {item}" for item in summary.failed_sources]
    problems += [f"Quelle auffällig: {item}" for item in summary.drift]
    if summary.budget_reached:
        problems.append(
            f"Budget erreicht ({summary.cost_eur:.2f} €): {summary.deferred} "
            "Einträge warten auf den nächsten Lauf"
        )
    return problems


async def run_scheduler(runs: IngestionRuns, check_every: timedelta) -> None:
    """Checks forever whether a scheduled run is due; cancel to stop."""
    while True:
        try:
            await runs.run_if_due()
        except Exception:  # a DB hiccup must not end the loop
            logger.exception("Ingestion scheduler check failed")
        await asyncio.sleep(check_every.total_seconds())
