"""Tests for the DIP Reden (Plenarprotokolle) position-check adapter."""

from datetime import datetime
from unittest.mock import MagicMock, patch

from meinimpact.infrastructure.sources.dip_reden_adapter import DipRedenPositionAdapter
from meinimpact.infrastructure.sources.protocol import MdbTarget
from tests.support.httpx_mock import make_json_response, make_mock_client

_SINCE = datetime(2026, 4, 1)


async def test_found_true_when_descriptor_matches() -> None:
    client = make_mock_client(
        get_side_effect=[
            make_json_response(
                {
                    "documents": [
                        {
                            "id": "999",
                            "titel": "Rede zum Klimaschutzgesetz",
                            "deskriptor": [{"name": "Klimaschutz"}],
                        }
                    ]
                }
            )
        ]
    )
    with patch(
        "meinimpact.infrastructure.sources.dip_reden_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = DipRedenPositionAdapter(api_key="test-key")
        result = await adapter.check_position(
            MdbTarget(name="Sarah Müller", dip_person_id="123"),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )
    assert result.found is True
    assert result.source == "dip_reden"
    assert "999" in (result.source_url or "")


async def test_found_false_when_no_descriptor_matches() -> None:
    client = make_mock_client(
        get_side_effect=[
            make_json_response(
                {
                    "documents": [
                        {
                            "id": "999",
                            "titel": "Rede",
                            "deskriptor": [{"name": "Verkehr"}],
                        }
                    ]
                }
            )
        ]
    )
    with patch(
        "meinimpact.infrastructure.sources.dip_reden_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = DipRedenPositionAdapter(api_key="test-key")
        result = await adapter.check_position(
            MdbTarget(name="Sarah Müller", dip_person_id="123"),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )
    assert result.found is False


async def test_found_false_without_dip_person_id() -> None:
    adapter = DipRedenPositionAdapter(api_key="test-key")
    result = await adapter.check_position(
        MdbTarget(name="Sarah Müller"), descriptors=["klimaschutz"], since=_SINCE
    )
    assert result.found is False


async def test_request_uses_percent_encoding_and_expected_filters() -> None:
    captured: list[str] = []

    async def _capturing_get(url: str, **_: object) -> MagicMock:
        captured.append(url)
        return make_json_response({"documents": []})

    client = make_mock_client()
    client.get = _capturing_get
    with patch(
        "meinimpact.infrastructure.sources.dip_reden_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        adapter = DipRedenPositionAdapter(api_key="test-key")
        await adapter.check_position(
            MdbTarget(name="Sarah Müller", dip_person_id="123"),
            descriptors=["klimaschutz"],
            since=_SINCE,
        )

    assert len(captured) == 1
    url = captured[0]
    assert "f.person.id=123" in url
    assert "f.aktivitaetsart=Rede" in url
    assert "f.datum.start=2026-04-01" in url
    assert "+" not in url
