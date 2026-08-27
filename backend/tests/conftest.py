"""Shared pytest fixtures."""

from collections.abc import AsyncGenerator

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.core.config import Settings
from meinimpact.infrastructure.database import Database


@pytest.fixture
async def db_session() -> AsyncGenerator[AsyncSession]:
    """Real DB session, rolled back after each test to leave no side effects."""
    settings = Settings()
    db = Database(settings.database_url)
    async with db._session_factory() as session:
        yield session
        await session.rollback()
    await db.close()
