"""Unit tests for new PostgreSQL repository implementations."""

import uuid
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from meinimpact.infrastructure.actions.postgres_stats_repository import (
    PostgresActionStatsRepository,
)
from meinimpact.infrastructure.beta.postgres_beta_repository import (
    PostgresBetaTokenRepository,
)
from meinimpact.infrastructure.feedback.postgres_feedback_repository import (
    PostgresFeedbackRepository,
)
from meinimpact.infrastructure.push.postgres_push_repository import (
    PostgresPushSubscriptionRepository,
)
from meinimpact.infrastructure.tracking.postgres_tracking_repository import (
    PostgresTrackingRepository,
    _event_to_domain,
    _statement_to_domain,
)
from meinimpact.infrastructure.models import MdbStatementRecord, TrackingEventRecord


# ── Stats repository ──────────────────────────────────────────────────────────


async def test_stats_increment_returns_new_count() -> None:
    mock_row = MagicMock()
    mock_row.__getitem__ = lambda self, i: 3

    mock_result = MagicMock()
    mock_result.fetchone.return_value = mock_row

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresActionStatsRepository(session)
    count = await repo.increment_completion("some-action")

    assert count == 3
    session.commit.assert_awaited_once()


async def test_stats_increment_returns_1_when_no_row() -> None:
    mock_result = MagicMock()
    mock_result.fetchone.return_value = None

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresActionStatsRepository(session)
    count = await repo.increment_completion("some-action")

    assert count == 1


# ── Tracking repository ───────────────────────────────────────────────────────


async def test_tracking_list_events_returns_domain_objects() -> None:
    record = TrackingEventRecord()
    record.id = uuid.uuid4()
    record.action_id = "action-1"
    record.event_type = "vote_result"
    record.title = "Abstimmung: Angenommen"
    record.description = "Das Gesetz wurde angenommen."
    record.outcome = "positive"
    record.source_url = "https://example.com"
    record.occurred_at = datetime(2026, 6, 18, 14, 0, tzinfo=UTC)

    mock_result = MagicMock()
    mock_result.scalars.return_value.all.return_value = [record]

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresTrackingRepository(session)
    events = await repo.list_events("action-1")

    assert len(events) == 1
    assert events[0].event_type == "vote_result"
    assert events[0].outcome == "positive"


async def test_tracking_list_mdb_statements_returns_domain_objects() -> None:
    record = MdbStatementRecord()
    record.id = uuid.uuid4()
    record.action_id = "action-1"
    record.mdb_name = "Sarah Müller"
    record.mdb_aw_id = None
    record.found = True
    record.statement_summary = "Begrüßt den Beschluss."
    record.source_url = "https://example.com"
    record.searched_at = datetime(2026, 6, 18, 3, 0, tzinfo=UTC)

    mock_result = MagicMock()
    mock_result.scalars.return_value.all.return_value = [record]

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresTrackingRepository(session)
    statements = await repo.list_mdb_statements("action-1")

    assert len(statements) == 1
    assert statements[0].mdb_name == "Sarah Müller"
    assert statements[0].found is True


# ── Push repository ───────────────────────────────────────────────────────────


async def test_push_register_commits() -> None:
    session = AsyncMock()
    session.execute.return_value = MagicMock()

    repo = PostgresPushSubscriptionRepository(session)
    await repo.register("token-abc", "fcm")

    session.commit.assert_awaited_once()


async def test_push_subscribe_commits() -> None:
    session = AsyncMock()
    session.execute.return_value = MagicMock()

    repo = PostgresPushSubscriptionRepository(session)
    await repo.subscribe("token-abc", "action-1")

    session.commit.assert_awaited_once()


async def test_push_unsubscribe_commits() -> None:
    session = AsyncMock()
    session.execute.return_value = MagicMock()

    repo = PostgresPushSubscriptionRepository(session)
    await repo.unsubscribe("token-abc", "action-1")

    session.commit.assert_awaited_once()


# ── Feedback repository ───────────────────────────────────────────────────────


async def test_feedback_submit_commits() -> None:
    session = AsyncMock()
    session.execute.return_value = MagicMock()

    repo = PostgresFeedbackRepository(session)
    await repo.submit(action_id="action-1", rating=4, comment="Gut!")

    session.commit.assert_awaited_once()


async def test_feedback_submit_without_action_id() -> None:
    session = AsyncMock()
    session.execute.return_value = MagicMock()

    repo = PostgresFeedbackRepository(session)
    await repo.submit(action_id=None, rating=5, comment=None)

    session.commit.assert_awaited_once()


# ── Beta token repository ─────────────────────────────────────────────────────


async def test_beta_activate_returns_true_when_token_exists() -> None:
    mock_result = MagicMock()
    mock_result.fetchone.return_value = ("some-uuid",)

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresBetaTokenRepository(session)
    valid = await repo.activate("00000000-0000-0000-0000-000000000001")

    assert valid is True
    session.commit.assert_awaited_once()


async def test_beta_activate_returns_false_when_not_found() -> None:
    mock_result = MagicMock()
    mock_result.fetchone.return_value = None

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresBetaTokenRepository(session)
    valid = await repo.activate("00000000-0000-0000-0000-999999999999")

    assert valid is False


async def test_beta_activate_returns_false_for_invalid_uuid() -> None:
    session = AsyncMock()

    repo = PostgresBetaTokenRepository(session)
    valid = await repo.activate("not-a-uuid")

    assert valid is False
    session.execute.assert_not_called()
