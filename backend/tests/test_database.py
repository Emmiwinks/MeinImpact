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
    assert "user_profiles" in Base.metadata.tables
    assert "civic_actions" in Base.metadata.tables
    assert "news_items" in Base.metadata.tables
    assert "action_tracking" in Base.metadata.tables


def test_persistent_tables_avoid_direct_identity_columns() -> None:
    for table in Base.metadata.tables.values():
        assert "full_name" not in table.columns
        assert "street_address" not in table.columns
        assert "email_address" not in table.columns


def test_civic_actions_orm_columns_match_current_schema() -> None:
    """Guards against ORM/migration drift.

    If a column is added or dropped in a migration but the SQLAlchemy model
    isn't updated (or vice versa), this list goes stale and the test fails.
    Update it intentionally when the schema changes.
    """
    cols = {c.name for c in Base.metadata.tables["civic_actions"].columns}
    # Columns removed in migration 202606240007 must NOT appear in the ORM model.
    assert "topics" not in cols
    # momentum_score was removed in migration 202607100008 (engagement-state cutover).
    assert "momentum_score" not in cols
    # Core columns that must always be present.
    required = {
        "id",
        "title",
        "action_type",
        "summary",
        "region",
        "deadline",
        "effort_minutes",
        "impact_hint",
        "source_url",
        "urgency",
        "werte_relevanz",
        "active",
        "updated_at",
        "engagement_state",
        "state_reason",
        "pipeline_source",
        "previous_signature_count",
    }
    missing = required - cols
    assert not missing, f"ORM model is missing expected columns: {missing}"


def test_user_profiles_orm_columns_match_current_schema() -> None:
    """Same drift guard for user_profiles. topics was removed in 202606240007."""
    cols = {c.name for c in Base.metadata.tables["user_profiles"].columns}
    assert "topics" not in cols
    # The user's value axes are stored as `value_axes`, not `werte` — that
    # name belongs to `civic_actions.werte_relevanz` (migration 202606080004),
    # a different table entirely.
    assert "value_axes" in cols
