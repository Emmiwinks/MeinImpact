"""PostgreSQL-backed push subscription repository."""

from datetime import UTC, datetime

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


class PostgresPushSubscriptionRepository:
    """Manages anonymous push notification subscriptions."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def register(self, push_token: str, platform: str) -> None:
        """Upserts a push token registration."""
        await self._session.execute(
            text("""
                INSERT INTO push_subscriptions (push_token, platform, action_ids, updated_at)
                VALUES (:token, :platform, '{}', :now)
                ON CONFLICT (push_token) DO UPDATE
                    SET platform = :platform,
                        updated_at = :now
            """),
            {"token": push_token, "platform": platform, "now": datetime.now(UTC)},
        )
        await self._session.commit()

    async def subscribe(self, push_token: str, action_id: str) -> None:
        """Adds an action_id to the token's list if not already present."""
        await self._session.execute(
            text("""
                INSERT INTO push_subscriptions (push_token, platform, action_ids, updated_at)
                VALUES (:token, 'unknown', ARRAY[:action_id::text], :now)
                ON CONFLICT (push_token) DO UPDATE
                    SET action_ids = array_append(
                            array_remove(push_subscriptions.action_ids, :action_id),
                            :action_id
                        ),
                        updated_at = :now
            """),
            {"token": push_token, "action_id": action_id, "now": datetime.now(UTC)},
        )
        await self._session.commit()

    async def unsubscribe(self, push_token: str, action_id: str) -> None:
        """Removes an action_id from the token's list."""
        await self._session.execute(
            text("""
                UPDATE push_subscriptions
                SET action_ids = array_remove(action_ids, :action_id),
                    updated_at = :now
                WHERE push_token = :token
            """),
            {"token": push_token, "action_id": action_id, "now": datetime.now(UTC)},
        )
        await self._session.commit()
