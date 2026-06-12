"""PostgreSQL-backed beta token repository."""

import uuid
from datetime import UTC, datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


class PostgresBetaTokenRepository:
    """Validates and activates MVP beta access tokens."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def activate(self, token: str) -> bool:
        """Marks the token as used and returns True if it exists."""
        try:
            token_uuid = uuid.UUID(token)
        except ValueError:
            return False

        result = await self._session.execute(
            text("""
                UPDATE beta_tokens
                SET used = true,
                    activated_at = COALESCE(activated_at, :now)
                WHERE token = :token
                RETURNING token
            """),
            {"token": token_uuid, "now": datetime.now(UTC)},
        )
        await self._session.commit()
        return result.fetchone() is not None
