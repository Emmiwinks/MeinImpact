"""PostgreSQL-backed ingestion schedule and run history.

A run row in status `running` is the lock: claiming happens under a
transaction-scoped advisory lock, so two machines checking at the same moment
can't both start. A run whose machine died never finishes; it counts as
interrupted once it is older than `stale_after`.
"""

import json
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Literal

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

Trigger = Literal["scheduled", "manual"]

# Arbitrary constant naming the claim lock in pg_advisory_xact_lock.
_CLAIM_LOCK_KEY = 7_202_611_080
_INTERRUPTED = "Unterbrochen (Maschine neu gestartet oder gestoppt)"


@dataclass(frozen=True)
class Schedule:
    enabled: bool
    interval_hours: int


@dataclass(frozen=True)
class RunRecord:
    id: int
    trigger: str
    status: str
    started_at: datetime
    finished_at: datetime | None
    summary: dict[str, Any] | None
    error: str | None


class PostgresIngestionRunRepository:
    """Reads and writes the schedule row and the run history."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def schedule(self) -> Schedule:
        row = (
            await self._session.execute(
                text("SELECT enabled, interval_hours FROM ingestion_schedule")
            )
        ).one()
        return Schedule(enabled=row.enabled, interval_hours=row.interval_hours)

    async def set_schedule(self, schedule: Schedule, *, now: datetime) -> None:
        await self._session.execute(
            text("""
                UPDATE ingestion_schedule
                SET enabled = :enabled, interval_hours = :interval_hours,
                    updated_at = :now
            """),
            {
                "enabled": schedule.enabled,
                "interval_hours": schedule.interval_hours,
                "now": now,
            },
        )
        await self._session.commit()

    async def claim(
        self, trigger: Trigger, *, now: datetime, stale_after: timedelta
    ) -> int | None:
        """Starts a run and returns its id, or None if one may not start now.

        Manual runs start whenever no run is in progress. Scheduled runs also
        need the schedule enabled and the interval passed since the last run
        of any kind, so a manual run postpones the next scheduled one.
        """
        await self._session.execute(
            text("SELECT pg_advisory_xact_lock(:key)"), {"key": _CLAIM_LOCK_KEY}
        )
        await self._session.execute(
            text("""
                UPDATE ingestion_runs
                SET status = 'failed', finished_at = :now, error = :error
                WHERE status = 'running' AND started_at < :stale_before
            """),
            {"now": now, "stale_before": now - stale_after, "error": _INTERRUPTED},
        )
        running = (
            await self._session.execute(
                text("SELECT 1 FROM ingestion_runs WHERE status = 'running' LIMIT 1")
            )
        ).first()
        if running is not None or (
            trigger == "scheduled" and not await self._is_due(now)
        ):
            await self._session.commit()
            return None
        run_id = (
            await self._session.execute(
                text("""
                    INSERT INTO ingestion_runs (trigger, status, started_at)
                    VALUES (:trigger, 'running', :now)
                    RETURNING id
                """),
                {"trigger": trigger, "now": now},
            )
        ).scalar_one()
        await self._session.commit()
        return int(run_id)

    async def finish(
        self,
        run_id: int,
        *,
        now: datetime,
        summary: dict[str, Any] | None,
        error: str | None,
    ) -> None:
        await self._session.execute(
            text("""
                UPDATE ingestion_runs
                SET status = :status, finished_at = :now,
                    summary = CAST(:summary AS jsonb), error = :error
                WHERE id = :id
            """),
            {
                "id": run_id,
                "status": "failed" if error else "succeeded",
                "now": now,
                "summary": json.dumps(summary) if summary is not None else None,
                "error": error,
            },
        )
        await self._session.commit()

    async def recent(self, limit: int = 15) -> list[RunRecord]:
        rows = (
            await self._session.execute(
                text("""
                    SELECT id, trigger, status, started_at, finished_at,
                           summary, error
                    FROM ingestion_runs
                    ORDER BY started_at DESC
                    LIMIT :limit
                """),
                {"limit": limit},
            )
        ).all()
        return [
            RunRecord(
                id=row.id,
                trigger=row.trigger,
                status=row.status,
                started_at=row.started_at,
                finished_at=row.finished_at,
                summary=row.summary,
                error=row.error,
            )
            for row in rows
        ]

    async def _is_due(self, now: datetime) -> bool:
        schedule = await self.schedule()
        if not schedule.enabled:
            return False
        last = (
            await self._session.execute(
                text("SELECT max(started_at) FROM ingestion_runs")
            )
        ).scalar_one()
        return last is None or last + timedelta(hours=schedule.interval_hours) <= now
