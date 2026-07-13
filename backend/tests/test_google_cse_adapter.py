"""Tests for the Google Custom Search fallback adapter."""

from unittest.mock import patch

from meinimpact.infrastructure.sources.google_cse_adapter import GoogleCseAdapter
from tests.support.httpx_mock import make_json_response, make_mock_client


async def test_returns_items_on_success():
    client = make_mock_client(
        get_side_effect=[make_json_response({"items": [{"link": "https://openpetition.de/1"}]})]
    )
    with patch(
        "meinimpact.infrastructure.sources.google_cse_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = GoogleCseAdapter(api_key="key", cse_id="cse-id")
        results = await adapter.search("Petition unterzeichnen")
    assert results == [{"link": "https://openpetition.de/1"}]


async def test_returns_empty_list_when_no_items_key():
    client = make_mock_client(get_side_effect=[make_json_response({})])
    with patch(
        "meinimpact.infrastructure.sources.google_cse_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = GoogleCseAdapter(api_key="key", cse_id="cse-id")
        results = await adapter.search("Petition unterzeichnen")
    assert results == []


async def test_returns_empty_list_on_quota_error():
    client = make_mock_client(get_side_effect=[Exception("403 quota exceeded")])
    with patch(
        "meinimpact.infrastructure.sources.google_cse_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = GoogleCseAdapter(api_key="key", cse_id="cse-id")
        results = await adapter.search("Petition unterzeichnen")
    assert results == []


async def test_request_params_use_key_cx_and_query():
    captured: list[dict[str, object]] = []

    async def _capturing_get(url: str, params: dict[str, object] | None = None, **_: object):
        captured.append({"url": url, "params": params})
        return make_json_response({"items": []})

    client = make_mock_client()
    client.get = _capturing_get
    with patch(
        "meinimpact.infrastructure.sources.google_cse_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = GoogleCseAdapter(api_key="my-key", cse_id="my-cse")
        await adapter.search("site:openpetition.de Petition", max_results=20)

    assert len(captured) == 1
    assert captured[0]["params"] == {
        "key": "my-key",
        "cx": "my-cse",
        "q": "site:openpetition.de Petition",
        "num": 10,  # clamped to the API's hard limit
    }
