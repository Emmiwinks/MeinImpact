"""PostgreSQL-backed action completion stats repository."""

from datetime import UTC, datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


class PostgresActionStatsRepository:
    """Increments and reads anonymous completion counters."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def increment_completion(self, action_id: str) -> int:
        """Upserts a completion count row and returns the new total."""
        result = await self._session.execute(
            text("""
                INSERT INTO action_stats (action_id, completion_count, updated_at)
                VALUES (:action_id, 1, :now)
                ON CONFLICT (action_id) DO UPDATE
                    SET completion_count = action_stats.completion_count + 1,
                        updated_at = :now
                RETURNING completion_count
            """),
            {"action_id": action_id, "now": datetime.now(UTC)},
        )
        await self._session.commit()
        row = result.fetchone()
        return int(row[0]) if row else 1
