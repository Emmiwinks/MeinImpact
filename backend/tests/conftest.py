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
    async with db.session_factory() as session:
        yield session
        await session.rollback()
    await db.close()


@pytest.fixture
async def committing_db_session() -> AsyncGenerator[AsyncSession]:
    """Real DB session for code that commits: its commits become savepoints
    inside one outer transaction that is rolled back after the test."""
    db = Database(Settings().database_url)
    async with db.engine.connect() as connection:
        transaction = await connection.begin()
        session = AsyncSession(
            bind=connection,
            join_transaction_mode="create_savepoint",
            expire_on_commit=False,
        )
        yield session
        await session.close()
        await transaction.rollback()
    await db.close()
