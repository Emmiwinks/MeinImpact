"""Tests for the PostgreSQL-backed opportunity repository."""

from datetime import UTC, date, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from meinimpact.infrastructure.ai.opportunity_extractor import ExtractedOpportunity
from meinimpact.infrastructure.models import OpportunityRecord
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
    UpsertOutcome,
)


def _extracted(**overrides: object) -> ExtractedOpportunity:
    base: ExtractedOpportunity = {
        "decision_object": "Mietendeckel einführen",
        "plain_language_title": "Soll ein Mietendeckel eingeführt werden?",
        "plain_language_summary": "Zusammenfassung.",
        "affected_tags": ["Wohnen/Miete"],
        "werte_relevanz": {"equality_markets": -0.8},
        "deadline": None,
        "support_count": None,
        "support_count_as_of": None,
        "content_published_at": None,
        "pro_argumente": ["Argument 1"],
        "contra_argumente": ["Gegenargument 1"],
        "personal_impact_snippets": {},
        "action_types": ["petition"],
    }
    base.update(overrides)  # type: ignore[typeddict-item]
    return base


def _no_match_result() -> MagicMock:
    result = MagicMock()
    result.scalar_one_or_none.return_value = None
    result.scalars.return_value.first.return_value = None
    return result


def _match_result(record: OpportunityRecord) -> MagicMock:
    result = MagicMock()
    result.scalar_one_or_none.return_value = record
    result.scalars.return_value.first.return_value = record
    return result


def _scalars_all_result(records: list[OpportunityRecord]) -> MagicMock:
    result = MagicMock()
    result.scalars.return_value.all.return_value = records
    return result


async def test_upsert_inserts_when_no_existing_match() -> None:
    session = AsyncMock()
    session.execute = AsyncMock(side_effect=[_no_match_result(), _no_match_result()])
    session.add = MagicMock()  # session.add() is synchronous in real SQLAlchemy
    repo = PostgresOpportunityRepository(session)
    run_id = uuid4()

    outcome = await repo.upsert(
        extracted=_extracted(),
        embedding=[0.1] * 1024,
        source_org="openPetition",
        source_url="https://openpetition.de/petition/online/x",
        region="bund",
        run_id=run_id,
    )

    assert outcome is UpsertOutcome.INSERTED
    session.add.assert_called_once()
    added = session.add.call_args.args[0]
    assert isinstance(added, OpportunityRecord)
    assert added.decision_object == "Mietendeckel einführen"
    assert added.source_url == "https://openpetition.de/petition/online/x"
    assert added.last_seen_run_id == run_id
    session.commit.assert_awaited_once()


async def test_upsert_refreshes_on_exact_url_match() -> None:
    existing = OpportunityRecord(
        source_url="https://openpetition.de/petition/online/x",
        support_count=100,
        deadline=None,
    )
    session = AsyncMock()
    session.execute = AsyncMock(side_effect=[_match_result(existing)])
    repo = PostgresOpportunityRepository(session)
    run_id = uuid4()

    outcome = await repo.upsert(
        extracted=_extracted(
            support_count=200, support_count_as_of=datetime(2026, 9, 27, tzinfo=UTC)
        ),
        embedding=[0.1] * 1024,
        source_org="openPetition",
        source_url="https://openpetition.de/petition/online/x",
        region="bund",
        run_id=run_id,
    )

    assert outcome is UpsertOutcome.REFRESHED
    session.add.assert_not_called()
    assert existing.support_count == 200
    assert existing.last_seen_run_id == run_id
    session.commit.assert_awaited_once()


async def test_upsert_refreshes_on_embedding_similarity_match_when_url_differs() -> None:
    existing = OpportunityRecord(
        source_url="https://weact.campact.de/petitions/other-slug",
        support_count=None,
        deadline=None,
    )
    session = AsyncMock()
    session.execute = AsyncMock(
        side_effect=[_no_match_result(), _match_result(existing)]
    )
    repo = PostgresOpportunityRepository(session)

    outcome = await repo.upsert(
        extracted=_extracted(),
        embedding=[0.1] * 1024,
        source_org="openPetition",
        source_url="https://openpetition.de/petition/online/new-slug",
        region="bund",
        run_id=uuid4(),
    )

    assert outcome is UpsertOutcome.REFRESHED
    session.add.assert_not_called()


async def test_refresh_does_not_null_out_support_count_when_new_run_found_none() -> None:
    existing = OpportunityRecord(
        source_url="https://openpetition.de/petition/online/x",
        support_count=100,
        support_count_as_of=datetime(2026, 1, 1, tzinfo=UTC),
        deadline=date(2026, 6, 1),
    )
    session = AsyncMock()
    session.execute = AsyncMock(side_effect=[_match_result(existing)])
    repo = PostgresOpportunityRepository(session)

    await repo.upsert(
        extracted=_extracted(support_count=None, deadline=None),
        embedding=[0.1] * 1024,
        source_org="openPetition",
        source_url="https://openpetition.de/petition/online/x",
        region="bund",
        run_id=uuid4(),
    )

    # A run that couldn't extract a count/deadline must not erase a
    # previously-known one.
    assert existing.support_count == 100
    assert existing.deadline == date(2026, 6, 1)


async def test_refresh_never_touches_retrieved_at() -> None:
    original_retrieved_at = datetime(2026, 1, 1, tzinfo=UTC)
    existing = OpportunityRecord(
        source_url="https://openpetition.de/petition/online/x",
        retrieved_at=original_retrieved_at,
    )
    session = AsyncMock()
    session.execute = AsyncMock(side_effect=[_match_result(existing)])
    repo = PostgresOpportunityRepository(session)

    await repo.upsert(
        extracted=_extracted(support_count=500),
        embedding=[0.1] * 1024,
        source_org="openPetition",
        source_url="https://openpetition.de/petition/online/x",
        region="bund",
        run_id=uuid4(),
    )

    assert existing.retrieved_at == original_retrieved_at


async def test_list_current_run_returns_empty_when_no_run_has_happened() -> None:
    session = AsyncMock()
    no_run = MagicMock()
    no_run.scalar_one_or_none.return_value = None
    session.execute = AsyncMock(return_value=no_run)
    repo = PostgresOpportunityRepository(session)

    result = await repo.list_current_run()

    assert result == []


async def test_list_current_run_only_returns_rows_matching_latest_run_id() -> None:
    latest_run_id = uuid4()
    matching_record = OpportunityRecord(
        source_url="https://openpetition.de/petition/online/current",
        last_seen_run_id=latest_run_id,
        affected_tags=[],
        action_types=["petition"],
        pro_argumente=[],
        contra_argumente=[],
        personal_impact_snippets={},
        werte_relevanz={},
    )
    latest_run_lookup = MagicMock()
    latest_run_lookup.scalar_one_or_none.return_value = latest_run_id
    rows_result = _scalars_all_result([matching_record])

    session = AsyncMock()
    session.execute = AsyncMock(side_effect=[latest_run_lookup, rows_result])
    repo = PostgresOpportunityRepository(session)

    result = await repo.list_current_run()

    assert len(result) == 1
    assert result[0].source_url == "https://openpetition.de/petition/online/current"
