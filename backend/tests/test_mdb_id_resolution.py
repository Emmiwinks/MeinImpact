"""Tests for MdB DIP-person-ID resolution and caching."""

from unittest.mock import patch

from meinimpact.infrastructure.mdb.mdb_id_resolution import (
    InMemoryMdbIdCache,
    MdbIdResolver,
)
from tests.support.httpx_mock import make_json_response, make_mock_client


async def test_cache_miss_resolves_and_caches():
    client = make_mock_client(
        get_side_effect=[make_json_response({"documents": [{"id": "999"}]})]
    )
    cache = InMemoryMdbIdCache()
    with patch(
        "meinimpact.infrastructure.mdb.mdb_id_resolution.httpx.AsyncClient",
        return_value=client,
    ):
        resolver = MdbIdResolver(api_key="test-key", cache=cache)
        result = await resolver.resolve("Sarah Müller")

    assert result == "999"
    assert await cache.get("Sarah Müller") == "999"


async def test_cache_hit_does_not_call_dip():
    cache = InMemoryMdbIdCache()
    await cache.set("Sarah Müller", "cached-id")
    client = make_mock_client(get_side_effect=[Exception("should not be called")])
    with patch(
        "meinimpact.infrastructure.mdb.mdb_id_resolution.httpx.AsyncClient",
        return_value=client,
    ):
        resolver = MdbIdResolver(api_key="test-key", cache=cache)
        result = await resolver.resolve("Sarah Müller")

    assert result == "cached-id"


async def test_no_matching_person_returns_none_and_does_not_cache():
    client = make_mock_client(get_side_effect=[make_json_response({"documents": []})])
    cache = InMemoryMdbIdCache()
    with patch(
        "meinimpact.infrastructure.mdb.mdb_id_resolution.httpx.AsyncClient",
        return_value=client,
    ):
        resolver = MdbIdResolver(api_key="test-key", cache=cache)
        result = await resolver.resolve("Unknown Person")

    assert result is None
    assert await cache.get("Unknown Person") is None


async def test_request_error_returns_none():
    client = make_mock_client(get_side_effect=[Exception("network error")])
    cache = InMemoryMdbIdCache()
    with patch(
        "meinimpact.infrastructure.mdb.mdb_id_resolution.httpx.AsyncClient",
        return_value=client,
    ):
        resolver = MdbIdResolver(api_key="test-key", cache=cache)
        result = await resolver.resolve("Sarah Müller")

    assert result is None


async def test_request_uses_name_filter_with_percent_encoding():
    captured: list[str] = []

    async def _capturing_get(url: str, **_: object):
        captured.append(url)
        return make_json_response({"documents": []})

    client = make_mock_client()
    client.get = _capturing_get
    cache = InMemoryMdbIdCache()
    with patch(
        "meinimpact.infrastructure.mdb.mdb_id_resolution.httpx.AsyncClient",
        return_value=client,
    ):
        resolver = MdbIdResolver(api_key="test-key", cache=cache)
        await resolver.resolve("Sarah Müller")

    assert len(captured) == 1
    assert "f.name=Sarah" in captured[0]
    assert "%20" in captured[0] or "M" in captured[0]  # space between names is encoded
    assert "+" not in captured[0]


async def test_in_memory_cache_get_set_roundtrip():
    cache = InMemoryMdbIdCache()
    assert await cache.get("x") is None
    await cache.set("x", "123")
    assert await cache.get("x") == "123"
