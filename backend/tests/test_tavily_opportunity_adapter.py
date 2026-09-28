"""Tests for the Tavily-based opportunity discovery adapter."""

from typing import cast
from unittest.mock import AsyncMock

from meinimpact.infrastructure.sources.tavily_client import TavilyClient
from meinimpact.infrastructure.sources.tavily_opportunity_adapter import (
    REGIONS,
    TavilyOpportunityAdapter,
)


def _fake_client(results: list[dict[str, object]]) -> AsyncMock:
    client = AsyncMock()
    client.search = AsyncMock(return_value=results)
    return client


async def test_fetch_uses_region_query_and_allowlist() -> None:
    client = _fake_client([])
    adapter = TavilyOpportunityAdapter(cast(TavilyClient, client))

    await adapter.fetch("bund")

    client.search.assert_awaited_once()
    call = client.search.await_args
    assert call.args[0] == REGIONS["bund"].query
    assert call.kwargs["include_domains"] == REGIONS["bund"].allowlist


async def test_fetch_drops_results_outside_allowlist_even_if_returned() -> None:
    """include_domains isn't a hard guarantee from Tavily — a code-level
    filter must drop anything outside the allowlist regardless."""
    client = _fake_client(
        [
            {"title": "On-topic", "url": "https://openpetition.de/petition/online/x"},
            {"title": "Leaked news article", "url": "https://tagesschau.de/a1"},
        ]
    )
    adapter = TavilyOpportunityAdapter(cast(TavilyClient, client))

    items = await adapter.fetch("bund")

    assert len(items) == 1
    assert items[0]["domain"] == "openpetition.de"


async def test_fetch_applies_path_allowlist() -> None:
    client = _fake_client(
        [
            {"title": "Real petition", "url": "https://openpetition.de/petition/online/x"},
            {"title": "Blog post", "url": "https://openpetition.de/blog/some-post"},
        ]
    )
    adapter = TavilyOpportunityAdapter(cast(TavilyClient, client))

    items = await adapter.fetch("bund")

    assert [i["url"] for i in items] == ["https://openpetition.de/petition/online/x"]


async def test_fetch_applies_path_blocklist() -> None:
    client = _fake_client(
        [
            {
                "title": "Real consultation",
                "url": "https://buergerbeteiligung.sachsen.de/portal/sms/beteiligung/themen/1",
            },
            {
                "title": "Accessibility statement",
                "url": "https://buergerbeteiligung.sachsen.de/portal/sachsen/informationen/barrierefreiheit",
            },
        ]
    )
    adapter = TavilyOpportunityAdapter(cast(TavilyClient, client))

    items = await adapter.fetch("sachsen")

    assert len(items) == 1
    assert "informationen" not in items[0]["url"]


async def test_fetch_deduplicates_query_param_variants() -> None:
    client = _fake_client(
        [
            {
                "title": "German",
                "url": "https://buergerbeteiligung.sachsen.de/portal/sachsen/startseite",
            },
            {
                "title": "Same page, different lang param",
                "url": "https://buergerbeteiligung.sachsen.de/portal/sachsen/startseite?prefLang=cs",
            },
        ]
    )
    # startseite has no path filter entry so both would otherwise pass —
    # this isolates the query-param dedup behaviour.
    adapter = TavilyOpportunityAdapter(cast(TavilyClient, client))

    items = await adapter.fetch("sachsen")

    assert len(items) == 1


async def test_source_org_is_mapped_from_domain() -> None:
    client = _fake_client(
        [{"title": "x", "url": "https://weact.campact.de/petitions/x"}]
    )
    adapter = TavilyOpportunityAdapter(cast(TavilyClient, client))

    items = await adapter.fetch("bund")

    assert items[0]["source_org"] == "WeAct/Campact"


async def test_region_is_stamped_on_every_item() -> None:
    client = _fake_client(
        [{"title": "x", "url": "https://openpetition.de/petition/online/x"}]
    )
    adapter = TavilyOpportunityAdapter(cast(TavilyClient, client))

    items = await adapter.fetch("dresden")

    assert items[0]["region"] == "dresden"
