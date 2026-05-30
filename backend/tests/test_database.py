"""Database infrastructure tests."""

import pytest

from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.models import Base


@pytest.mark.asyncio
async def test_database_creates_sessions_without_process_state() -> None:
    database = Database("postgresql+psycopg://user:password@localhost/test")
    async for session in database.session():
        assert session is not None
        break
    await database.close()


def test_models_register_expected_tables() -> None:
    assert "user_profiles" in Base.metadata.tables
    assert "civic_actions" in Base.metadata.tables
