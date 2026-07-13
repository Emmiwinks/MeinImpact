"""Tests for the civil-society petition adapter (WeAct/openpetition + CSE fallback)."""

from datetime import datetime
from unittest.mock import AsyncMock

import pytest

from meinimpact.infrastructure.sources.civil_petition_adapter import CivilPetitionAdapter

_SINCE = datetime(2026, 1, 1)


def _fake_tavily(results: list[dict[str, object]]) -> object:
    client = AsyncMock()
    client.search = AsyncMock(return_value=results)
    return client


def _fake_cse(items: list[dict[str, object]]) -> object:
    client = AsyncMock()
    client.search = AsyncMock(return_value=items)
    return client


async def test_returns_valid_weact_petition():
    tavily = _fake_tavily(
        [{"url": "https://weact.campact.de/p/klimaschutz-jetzt", "title": "Klimaschutz jetzt", "content": "..."}]
    )
    adapter = CivilPetitionAdapter(tavily=tavily)
    items = await adapter.fetch_new_items(_SINCE)
    assert len(items) == 1
    assert items[0]["source"] == "tavily_petition_search"
    assert items[0]["type"] == "petition"


async def test_filters_out_non_petition_path():
    tavily = _fake_tavily(
        [{"url": "https://openpetition.de/blog/update-1", "title": "Update", "content": "..."}]
    )
    adapter = CivilPetitionAdapter(tavily=tavily)
    items = await adapter.fetch_new_items(_SINCE)
    assert items == []


async def test_filters_out_austrian_section():
    tavily = _fake_tavily(
        [{"url": "https://openpetition.de/at/petition/klimaschutz", "title": "x", "content": "..."}]
    )
    adapter = CivilPetitionAdapter(tavily=tavily)
    items = await adapter.fetch_new_items(_SINCE)
    assert items == []


async def test_filters_out_unrelated_domain():
    tavily = _fake_tavily([{"url": "https://example.com/petition/x", "title": "x", "content": "..."}])
    adapter = CivilPetitionAdapter(tavily=tavily)
    items = await adapter.fetch_new_items(_SINCE)
    assert items == []


async def test_falls_back_to_google_cse_when_tavily_empty():
    tavily = _fake_tavily([])
    cse = _fake_cse(
        [{"link": "https://openpetition.de/petition/klimaschutz", "title": "Klimaschutz", "snippet": "..."}]
    )
    adapter = CivilPetitionAdapter(tavily=tavily, google_cse=cse)
    items = await adapter.fetch_new_items(_SINCE)
    assert len(items) == 1
    assert items[0]["source"] == "google_cse_petition_search"


async def test_does_not_fall_back_when_tavily_has_results():
    tavily = _fake_tavily(
        [{"url": "https://weact.campact.de/petitions/x", "title": "x", "content": "..."}]
    )
    cse = _fake_cse([{"link": "https://openpetition.de/petition/other"}])
    adapter = CivilPetitionAdapter(tavily=tavily, google_cse=cse)
    await adapter.fetch_new_items(_SINCE)
    cse.search.assert_not_called()


async def test_no_fallback_when_google_cse_not_configured():
    tavily = _fake_tavily([])
    adapter = CivilPetitionAdapter(tavily=tavily, google_cse=None)
    items = await adapter.fetch_new_items(_SINCE)
    assert items == []


async def test_fetch_item_detail_not_implemented():
    adapter = CivilPetitionAdapter(tavily=_fake_tavily([]))
    with pytest.raises(NotImplementedError):
        await adapter.fetch_item_detail("some-id")
