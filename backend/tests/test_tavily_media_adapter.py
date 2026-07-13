"""Tests for the Tavily quality-media coverage adapter (state C)."""

from unittest.mock import AsyncMock

from meinimpact.infrastructure.sources.tavily_media_adapter import (
    QUALITY_MEDIA_DOMAINS,
    TavilyMediaCoverageAdapter,
)


def _fake_tavily_client(results: list[dict[str, object]]) -> object:
    client = AsyncMock()
    client.search = AsyncMock(return_value=results)
    return client


async def test_matches_with_two_articles_two_domains():
    client = _fake_tavily_client(
        [
            {"url": "https://tagesschau.de/a1"},
            {"url": "https://zeit.de/a2"},
        ]
    )
    adapter = TavilyMediaCoverageAdapter(client)
    result = await adapter.check_coverage("Klimaschutzgesetz")
    assert result.matched is True
    assert result.article_count == 2
    assert result.distinct_domains == 2


async def test_does_not_match_with_two_articles_same_domain():
    client = _fake_tavily_client(
        [
            {"url": "https://tagesschau.de/a1"},
            {"url": "https://tagesschau.de/a2"},
        ]
    )
    adapter = TavilyMediaCoverageAdapter(client)
    result = await adapter.check_coverage("Klimaschutzgesetz")
    assert result.matched is False
    assert result.distinct_domains == 1


async def test_does_not_match_with_one_article():
    client = _fake_tavily_client([{"url": "https://tagesschau.de/a1"}])
    adapter = TavilyMediaCoverageAdapter(client)
    result = await adapter.check_coverage("Klimaschutzgesetz")
    assert result.matched is False


async def test_does_not_match_with_no_results():
    client = _fake_tavily_client([])
    adapter = TavilyMediaCoverageAdapter(client)
    result = await adapter.check_coverage("Klimaschutzgesetz")
    assert result.matched is False
    assert result.article_count == 0


async def test_www_prefix_is_stripped_for_domain_counting():
    client = _fake_tavily_client(
        [
            {"url": "https://www.tagesschau.de/a1"},
            {"url": "https://tagesschau.de/a2"},
        ]
    )
    adapter = TavilyMediaCoverageAdapter(client)
    result = await adapter.check_coverage("Klimaschutzgesetz")
    # Same domain once www. is stripped — should NOT count as 2 distinct domains.
    assert result.distinct_domains == 1
    assert result.matched is False


async def test_search_called_with_quality_media_domains_and_correct_window():
    client = _fake_tavily_client([])
    adapter = TavilyMediaCoverageAdapter(client)
    await adapter.check_coverage("Klimaschutzgesetz")
    client.search.assert_awaited_once_with(
        "Klimaschutzgesetz",
        include_domains=QUALITY_MEDIA_DOMAINS,
        days=14,
        max_results=5,
    )
