"""Tests for the opportunity ingestion pipeline orchestration."""

from unittest.mock import AsyncMock

from meinimpact.infrastructure.ai.opportunity_extractor import ExtractedOpportunity
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    UpsertOutcome,
)
from meinimpact.infrastructure.pipeline.opportunity_pipeline import run_ingestion
from meinimpact.infrastructure.sources.tavily_opportunity_adapter import (
    RawOpportunityItem,
)


def _item(url: str, region: str = "bund") -> RawOpportunityItem:
    return RawOpportunityItem(
        title="t",
        url=url,
        domain="openpetition.de",
        source_org="openPetition",
        content="c",
        region=region,
    )


def _extracted(decision_object: str = "x") -> ExtractedOpportunity:
    return {
        "decision_object": decision_object,
        "plain_language_title": "t",
        "plain_language_summary": "s",
        "affected_tags": [],
        "werte_relevanz": {},
        "deadline": None,
        "support_count": None,
        "support_count_as_of": None,
        "content_published_at": None,
        "pro_argumente": [],
        "contra_argumente": [],
        "personal_impact_snippets": {},
        "action_types": ["petition"],
    }


def _mocks(fetch_by_region: dict[str, list[RawOpportunityItem]]):
    source = AsyncMock()
    source.fetch = AsyncMock(side_effect=lambda region: fetch_by_region.get(region, []))
    extractor = AsyncMock()
    embedder = AsyncMock()
    repository = AsyncMock()
    return source, extractor, embedder, repository


async def test_fetches_every_region_by_default() -> None:
    source, extractor, embedder, repository = _mocks(
        {"bund": [], "sachsen": [], "dresden": []}
    )
    extractor.extract = AsyncMock(return_value=None)

    summary = await run_ingestion(
        source=source, extractor=extractor, embedder=embedder, repository=repository
    )

    assert source.fetch.await_count == 3
    assert summary.fetched == 0
    assert summary.actionable == 0


async def test_can_be_scoped_to_specific_regions() -> None:
    source, extractor, embedder, repository = _mocks({"bund": []})
    extractor.extract = AsyncMock(return_value=None)

    await run_ingestion(
        source=source,
        extractor=extractor,
        embedder=embedder,
        repository=repository,
        regions=["bund"],
    )

    source.fetch.assert_awaited_once_with("bund")


async def test_non_actionable_items_are_skipped_without_embedding_or_persisting() -> (
    None
):
    item = _item("https://openpetition.de/petition/online/x")
    source, extractor, embedder, repository = _mocks({"bund": [item]})
    extractor.extract = AsyncMock(return_value=None)

    summary = await run_ingestion(
        source=source,
        extractor=extractor,
        embedder=embedder,
        repository=repository,
        regions=["bund"],
    )

    assert summary.fetched == 1
    assert summary.actionable == 0
    embedder.embed.assert_not_called()
    repository.upsert.assert_not_called()


async def test_actionable_item_gets_embedded_and_persisted() -> None:
    item = _item("https://openpetition.de/petition/online/x")
    source, extractor, embedder, repository = _mocks({"bund": [item]})
    extracted = _extracted()
    extractor.extract = AsyncMock(return_value=extracted)
    embedder.embed = AsyncMock(return_value=[0.1] * 1024)
    repository.upsert = AsyncMock(return_value=UpsertOutcome.INSERTED)

    summary = await run_ingestion(
        source=source,
        extractor=extractor,
        embedder=embedder,
        repository=repository,
        regions=["bund"],
    )

    embedder.embed.assert_awaited_once_with(extracted["decision_object"])
    repository.upsert.assert_awaited_once()
    call = repository.upsert.await_args.kwargs
    assert call["source_url"] == item["url"]
    assert call["source_org"] == item["source_org"]
    assert call["region"] == "bund"
    assert summary.actionable == 1
    assert summary.inserted == 1
    assert summary.refreshed == 0


async def test_refreshed_outcome_is_counted_separately_from_inserted() -> None:
    item = _item("https://openpetition.de/petition/online/x")
    source, extractor, embedder, repository = _mocks({"bund": [item]})
    extractor.extract = AsyncMock(return_value=_extracted())
    embedder.embed = AsyncMock(return_value=[0.1] * 1024)
    repository.upsert = AsyncMock(return_value=UpsertOutcome.REFRESHED)

    summary = await run_ingestion(
        source=source,
        extractor=extractor,
        embedder=embedder,
        repository=repository,
        regions=["bund"],
    )

    assert summary.inserted == 0
    assert summary.refreshed == 1


async def test_extraction_failure_is_recorded_and_does_not_abort_the_run() -> None:
    item = _item("https://openpetition.de/petition/online/x")
    source, extractor, embedder, repository = _mocks({"bund": [item]})
    extractor.extract = AsyncMock(side_effect=RuntimeError("mistral down"))

    summary = await run_ingestion(
        source=source,
        extractor=extractor,
        embedder=embedder,
        repository=repository,
        regions=["bund"],
    )

    assert summary.actionable == 0
    assert len(summary.errors) == 1
    assert "mistral down" in summary.errors[0]
    repository.upsert.assert_not_called()


async def test_persist_failure_is_recorded_and_does_not_abort_the_run() -> None:
    item = _item("https://openpetition.de/petition/online/x")
    source, extractor, embedder, repository = _mocks({"bund": [item]})
    extractor.extract = AsyncMock(return_value=_extracted())
    embedder.embed = AsyncMock(return_value=[0.1] * 1024)
    repository.upsert = AsyncMock(side_effect=RuntimeError("db down"))

    summary = await run_ingestion(
        source=source,
        extractor=extractor,
        embedder=embedder,
        repository=repository,
        regions=["bund"],
    )

    assert summary.inserted == 0
    assert summary.refreshed == 0
    assert any("db down" in e for e in summary.errors)
