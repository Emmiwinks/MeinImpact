"""Tests for the DIP committee-activity adapter (state A trigger #2)."""

from datetime import date
from unittest.mock import patch

from meinimpact.infrastructure.sources.dip_committee_activity import (
    DipCommitteeActivityAdapter,
)
from tests.support.httpx_mock import make_json_response, make_mock_client


async def test_returns_true_when_documents_found():
    client = make_mock_client(
        get_side_effect=[make_json_response({"documents": [{"id": "1"}]})]
    )
    with patch(
        "meinimpact.infrastructure.sources.dip_committee_activity.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = DipCommitteeActivityAdapter(api_key="test-key")
        result = await adapter.has_recent_activity("270050", since=date(2026, 6, 1))
    assert result is True


async def test_returns_false_when_no_documents():
    client = make_mock_client(get_side_effect=[make_json_response({"documents": []})])
    with patch(
        "meinimpact.infrastructure.sources.dip_committee_activity.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = DipCommitteeActivityAdapter(api_key="test-key")
        result = await adapter.has_recent_activity("270050", since=date(2026, 6, 1))
    assert result is False


async def test_returns_false_on_request_error():
    client = make_mock_client(get_side_effect=[Exception("network error")])
    with patch(
        "meinimpact.infrastructure.sources.dip_committee_activity.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = DipCommitteeActivityAdapter(api_key="test-key")
        result = await adapter.has_recent_activity("270050", since=date(2026, 6, 1))
    assert result is False


async def test_request_uses_expected_filter_params():
    captured: list[str] = []

    async def _capturing_get(url: str, **_: object):
        captured.append(url)
        return make_json_response({"documents": []})

    client = make_mock_client()
    client.get = _capturing_get
    with patch(
        "meinimpact.infrastructure.sources.dip_committee_activity.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = DipCommitteeActivityAdapter(api_key="test-key")
        await adapter.has_recent_activity("270050", since=date(2026, 6, 1))

    assert len(captured) == 1
    url = captured[0]
    assert "f.vorgangsbezug.id=270050" in url
    assert "f.aktivitaetsart=Ausschusssitzung" in url
    assert "f.datum.start=2026-06-01" in url
    assert "apikey=test-key" in url
