"""Database infrastructure tests."""

import pytest

from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.models import Base


@pytest.mark.asyncio
async def test_database_creates_sessions_without_process_state() -> None:
    database = Database("postgresql+asyncpg://user:password@localhost/test")
    async for session in database.session():
        assert session is not None
        break
    await database.close()


def test_models_register_expected_tables() -> None:
    assert "opportunities" in Base.metadata.tables
    assert "card_feedback" in Base.metadata.tables
    assert "beta_feedback" in Base.metadata.tables
    assert "news_items" in Base.metadata.tables


def test_retired_action_stack_tables_are_gone() -> None:
    """Dropped in migration 202611240026; the models must not come back."""
    retired = {
        "civic_actions",
        "user_profiles",
        "action_tracking",
        "beta_tokens",
        "push_subscriptions",
        "action_stats",
        "tracking_events",
        "mdb_statements",
    }
    assert not retired & set(Base.metadata.tables)


def test_persistent_tables_avoid_direct_identity_columns() -> None:
    for table in Base.metadata.tables.values():
        assert "full_name" not in table.columns
        assert "street_address" not in table.columns
        assert "email_address" not in table.columns
        assert "installation_id" not in table.columns
