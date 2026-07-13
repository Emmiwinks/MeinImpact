"""Tests for the Abgeordnetenwatch position-check adapter."""

from datetime import datetime
from unittest.mock import patch

from meinimpact.infrastructure.sources.abgeordnetenwatch_adapter import (
    AbgeordnetenwatchPositionAdapter,
)
from meinimpact.infrastructure.sources.protocol import MdbTarget
from tests.support.httpx_mock import make_json_response, make_mock_client

_SINCE = datetime(2026, 4, 1)


async def test_found_true_when_answer_text_matches_descriptor():
    client = make_mock_client(
        get_side_effect=[
            make_json_response(
                {"data": [{"text": "Ich unterstütze den Klimaschutz.", "url": "https://aw/1"}]}
            )
        ]
    )
    with patch(
        "meinimpact.infrastructure.sources.abgeordnetenwatch_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = AbgeordnetenwatchPositionAdapter()
        result = await adapter.check_position(
            MdbTarget(name="Sarah Müller", aw_politician_id=123),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )
    assert result.found is True
    assert result.source == "abgeordnetenwatch"
    assert result.source_url == "https://aw/1"


async def test_found_false_when_no_answer_matches():
    client = make_mock_client(
        get_side_effect=[make_json_response({"data": [{"text": "Irrelevant answer."}]})]
    )
    with patch(
        "meinimpact.infrastructure.sources.abgeordnetenwatch_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = AbgeordnetenwatchPositionAdapter()
        result = await adapter.check_position(
            MdbTarget(name="Sarah Müller", aw_politician_id=123),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )
    assert result.found is False
    assert result.source == "abgeordnetenwatch"


async def test_found_false_without_aw_politician_id():
    adapter = AbgeordnetenwatchPositionAdapter()
    result = await adapter.check_position(
        MdbTarget(name="Sarah Müller"), descriptors=["klimaschutz"], since=_SINCE
    )
    assert result.found is False


async def test_found_false_on_request_error():
    client = make_mock_client(get_side_effect=[Exception("boom")])
    with patch(
        "meinimpact.infrastructure.sources.abgeordnetenwatch_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = AbgeordnetenwatchPositionAdapter()
        result = await adapter.check_position(
            MdbTarget(name="Sarah Müller", aw_politician_id=123),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )
    assert result.found is False


async def test_request_uses_expected_params():
    captured: list[dict[str, object]] = []

    async def _capturing_get(url: str, params: dict[str, object] | None = None, **_: object):
        captured.append({"url": url, "params": params})
        return make_json_response({"data": []})

    client = make_mock_client()
    client.get = _capturing_get
    with patch(
        "meinimpact.infrastructure.sources.abgeordnetenwatch_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = AbgeordnetenwatchPositionAdapter()
        await adapter.check_position(
            MdbTarget(name="Sarah Müller", aw_politician_id=123),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )

    assert len(captured) == 1
    assert captured[0]["url"].endswith("/answers")
    assert captured[0]["params"] == {"politician": 123, "updated_since": "2026-04-01"}
