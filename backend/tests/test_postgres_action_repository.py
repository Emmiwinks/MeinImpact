"""Tests for the PostgreSQL-backed civic action repository."""

from datetime import UTC, date, datetime
from unittest.mock import AsyncMock, MagicMock

from meinimpact.domain.entities import ActionType, CivicAction
from meinimpact.infrastructure.actions.postgres_action_repository import (
    PostgresActionRepository,
    _to_domain,
)
from meinimpact.infrastructure.models import CivicActionRecord


def _make_record(action_id: str = "test-action") -> CivicActionRecord:
    record = CivicActionRecord()
    record.id = action_id
    record.title = "Testmaßnahme"
    record.action_type = ActionType.PETITION_SIGNATURE
    record.summary = "Eine Testzusammenfassung."
    record.topics = ["climate", "energy"]
    record.region = "Germany"
    record.deadline = date(2026, 12, 31)
    record.effort_minutes = 3
    record.impact_hint = "Der Ausgang ist öffentlich einsehbar."
    record.source_url = "https://epetitionen.bundestag.de/"
    record.urgency = "mid"
    record.werte_relevanz = {"wandel": 0.5}
    record.pro_argumente = ["Arg 1"]
    record.contra_argumente = ["Gegenarg 1"]
    record.action_types = ["petition"]
    record.is_controversial = False
    record.position_required = False
    record.momentum_score = 0.4
    record.active = True
    record.tavily_context = None
    record.updated_at = datetime(2026, 6, 8, 0, 0, tzinfo=UTC)
    return record


def test_to_domain_maps_record_to_civic_action() -> None:
    record = _make_record()
    action = _to_domain(record)

    assert isinstance(action, CivicAction)
    assert action.id == "test-action"
    assert action.action_type == ActionType.PETITION_SIGNATURE
    assert action.topics == ("climate", "energy")


async def test_list_open_actions_returns_all_records() -> None:
    records = [_make_record("action-1"), _make_record("action-2")]
    mock_result = MagicMock()
    mock_result.scalars.return_value.all.return_value = records

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresActionRepository(session)
    actions = await repo.list_open_actions()

    assert len(actions) == 2
    assert actions[0].id == "action-1"
    assert actions[1].id == "action-2"


async def test_get_action_returns_domain_object_when_found() -> None:
    record = _make_record("found-action")
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = record

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresActionRepository(session)
    action = await repo.get_action("found-action")

    assert action is not None
    assert action.id == "found-action"


async def test_get_action_returns_none_when_not_found() -> None:
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = None

    session = AsyncMock()
    session.execute.return_value = mock_result

    repo = PostgresActionRepository(session)
    action = await repo.get_action("missing")

    assert action is None
