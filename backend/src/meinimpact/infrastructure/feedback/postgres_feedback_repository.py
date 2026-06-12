"""PostgreSQL-backed anonymous feedback repository."""

from datetime import UTC, datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


class PostgresFeedbackRepository:
    """Stores anonymous in-app feedback."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def submit(
        self,
        action_id: str | None,
        rating: int | None,
        comment: str | None,
    ) -> None:
        """Inserts a feedback row."""
        await self._session.execute(
            text("""
                INSERT INTO feedback (action_id, rating, comment, created_at)
                VALUES (:action_id, :rating, :comment, :now)
            """),
            {
                "action_id": action_id,
                "rating": rating,
                "comment": comment,
                "now": datetime.now(UTC),
            },
        )
        await self._session.commit()
