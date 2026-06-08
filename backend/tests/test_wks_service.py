"""Tests for the WKS service — PLZ to MdB lookup."""

from unittest.mock import AsyncMock, MagicMock, patch

import httpx

from meinimpact.infrastructure.mdb.wks_service import (
    WksService,
    _build_indexes,
    _direktkandidat,
    _format_name,
)

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

_VALID_WKS_JSON = {
    "federalStates": [
        {
            "key": "SN",
            "name": "Sachsen",
            "constituencies": [
                {
                    "number": "159",
                    "name": "Dresden II - Bautzen II",
                    "mdbs": [
                        {
                            "name": "Rentzsch, Matthias",
                            "party": "AfD",
                            "first": True,
                            "link": "https://www.bundestag.de/rentzsch",
                        }
                    ],
                    "counties": [
                        {
                            "headline": "Dresden",
                            "communities": [
                                {
                                    "name": "Dresden, Stadt",
                                    "zipCodes": ["01454", "01900"],
                                }
                            ],
                        }
                    ],
                },
                {
                    "number": "160",
                    "name": "Dresden I",
                    "mdbs": [
                        {"name": "Müller, Anna", "party": "CDU", "first": False},
                        {"name": "Schmidt, Bernd", "party": "CDU", "first": True},
                    ],
                    "counties": [
                        {
                            "headline": "Dresden",
                            "communities": [
                                {"name": "Dresden-Mitte", "zipCodes": ["01067"]}
                            ],
                        }
                    ],
                },
            ],
        }
    ]
}


def _mock_httpx_client(status: int = 200, json_body: object = None) -> MagicMock:
    """Returns a mocked httpx.AsyncClient context manager."""
    response = MagicMock()
    response.status_code = status
    response.json = MagicMock(return_value=json_body or _VALID_WKS_JSON)
    client = AsyncMock()
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    client.get = AsyncMock(return_value=response)
    return client


# ---------------------------------------------------------------------------
# load()
# ---------------------------------------------------------------------------


async def test_load_success_populates_indexes() -> None:
    svc = WksService()
    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        return_value=_mock_httpx_client(),
    ):
        await svc.load()

    assert svc.is_healthy
    assert svc.load_error is None
    assert svc.lookup("01454") != []
    assert svc.lookup("01067") != []


async def test_load_network_error_sets_load_error() -> None:
    svc = WksService()
    client = AsyncMock()
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    client.get = AsyncMock(side_effect=httpx.ConnectError("unreachable"))

    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        return_value=client,
    ):
        await svc.load()

    assert not svc.is_healthy
    assert svc.load_error is not None


async def test_load_non_200_response_sets_load_error() -> None:
    svc = WksService()
    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        return_value=_mock_httpx_client(status=503),
    ):
        await svc.load()

    assert not svc.is_healthy
    assert "503" in (svc.load_error or "")


async def test_load_invalid_json_sets_load_error() -> None:
    svc = WksService()
    client = _mock_httpx_client()
    client.get.return_value.json = MagicMock(side_effect=ValueError("bad json"))

    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        return_value=client,
    ):
        await svc.load()

    assert not svc.is_healthy
    assert svc.load_error is not None


async def test_load_wrong_schema_sets_load_error() -> None:
    svc = WksService()
    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        return_value=_mock_httpx_client(json_body={"federalStates": [{"bad": True}]}),
    ):
        await svc.load()

    assert not svc.is_healthy


# ---------------------------------------------------------------------------
# lookup() and lookup_with_fallback()
# ---------------------------------------------------------------------------


async def test_lookup_returns_empty_for_unknown_plz() -> None:
    svc = WksService()
    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        return_value=_mock_httpx_client(),
    ):
        await svc.load()

    assert svc.lookup("99999") == []


async def test_lookup_with_fallback_hits_primary_index() -> None:
    svc = WksService()
    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        return_value=_mock_httpx_client(),
    ):
        await svc.load()
        results = await svc.lookup_with_fallback("01454")

    assert len(results) == 1
    assert results[0].wahlkreis_nr == 159


async def test_lookup_with_fallback_uses_autocomplete_for_missing_plz() -> None:
    svc = WksService()
    autocomplete_response = MagicMock()
    autocomplete_response.status_code = 200
    autocomplete_response.json = MagicMock(
        return_value={"results": [{"id": "159*~*01097", "text": "01097 - Dresden"}]}
    )

    wks_client = _mock_httpx_client()
    autocomplete_client = AsyncMock()
    autocomplete_client.__aenter__ = AsyncMock(return_value=autocomplete_client)
    autocomplete_client.__aexit__ = AsyncMock(return_value=False)
    autocomplete_client.get = AsyncMock(return_value=autocomplete_response)

    # First call (load) uses wks_client, second call (fallback) uses autocomplete_client
    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        side_effect=[wks_client, autocomplete_client],
    ):
        await svc.load()
        results = await svc.lookup_with_fallback("01097")

    assert len(results) == 1
    assert results[0].wahlkreis_nr == 159


async def test_lookup_with_fallback_no_autocomplete_results() -> None:
    svc = WksService()
    autocomplete_response = MagicMock()
    autocomplete_response.status_code = 200
    autocomplete_response.json = MagicMock(return_value={"results": []})

    wks_client = _mock_httpx_client()
    autocomplete_client = AsyncMock()
    autocomplete_client.__aenter__ = AsyncMock(return_value=autocomplete_client)
    autocomplete_client.__aexit__ = AsyncMock(return_value=False)
    autocomplete_client.get = AsyncMock(return_value=autocomplete_response)

    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        side_effect=[wks_client, autocomplete_client],
    ):
        await svc.load()
        results = await svc.lookup_with_fallback("99999")

    assert results == []


async def test_lookup_with_fallback_returns_empty_on_autocomplete_network_error() -> (
    None
):
    svc = WksService()
    wks_client = _mock_httpx_client()
    autocomplete_client = AsyncMock()
    autocomplete_client.__aenter__ = AsyncMock(return_value=autocomplete_client)
    autocomplete_client.__aexit__ = AsyncMock(return_value=False)
    autocomplete_client.get = AsyncMock(side_effect=httpx.ConnectError("unreachable"))

    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        side_effect=[wks_client, autocomplete_client],
    ):
        await svc.load()
        results = await svc.lookup_with_fallback("99999")

    assert results == []


async def test_lookup_with_fallback_returns_empty_on_autocomplete_non_200() -> None:
    svc = WksService()
    autocomplete_response = MagicMock()
    autocomplete_response.status_code = 503

    wks_client = _mock_httpx_client()
    autocomplete_client = AsyncMock()
    autocomplete_client.__aenter__ = AsyncMock(return_value=autocomplete_client)
    autocomplete_client.__aexit__ = AsyncMock(return_value=False)
    autocomplete_client.get = AsyncMock(return_value=autocomplete_response)

    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        side_effect=[wks_client, autocomplete_client],
    ):
        await svc.load()
        results = await svc.lookup_with_fallback("99999")

    assert results == []


async def test_lookup_with_fallback_returns_empty_on_autocomplete_invalid_json() -> (
    None
):
    svc = WksService()
    autocomplete_response = MagicMock()
    autocomplete_response.status_code = 200
    autocomplete_response.json = MagicMock(side_effect=ValueError("bad json"))

    wks_client = _mock_httpx_client()
    autocomplete_client = AsyncMock()
    autocomplete_client.__aenter__ = AsyncMock(return_value=autocomplete_client)
    autocomplete_client.__aexit__ = AsyncMock(return_value=False)
    autocomplete_client.get = AsyncMock(return_value=autocomplete_response)

    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        side_effect=[wks_client, autocomplete_client],
    ):
        await svc.load()
        results = await svc.lookup_with_fallback("99999")

    assert results == []


async def test_lookup_with_fallback_returns_empty_when_wk_not_in_index() -> None:
    """Autocomplete returns a Wahlkreis number that has no MdB in the index."""
    svc = WksService()
    autocomplete_response = MagicMock()
    autocomplete_response.status_code = 200
    autocomplete_response.json = MagicMock(
        return_value={"results": [{"id": "999*~*00000", "text": "unknown"}]}
    )

    wks_client = _mock_httpx_client()
    autocomplete_client = AsyncMock()
    autocomplete_client.__aenter__ = AsyncMock(return_value=autocomplete_client)
    autocomplete_client.__aexit__ = AsyncMock(return_value=False)
    autocomplete_client.get = AsyncMock(return_value=autocomplete_response)

    with patch(
        "meinimpact.infrastructure.mdb.wks_service.httpx.AsyncClient",
        side_effect=[wks_client, autocomplete_client],
    ):
        await svc.load()
        results = await svc.lookup_with_fallback("00000")

    assert results == []


# ---------------------------------------------------------------------------
# _build_indexes helpers
# ---------------------------------------------------------------------------


def test_build_indexes_prefers_direktkandidat() -> None:
    from meinimpact.infrastructure.mdb.wks_service import _WksRoot

    root = _WksRoot.model_validate(_VALID_WKS_JSON)
    _, wk_index = _build_indexes(root)

    # Constituency 160 has two MdBs; Schmidt (first=True) should win
    info = wk_index[160][0]
    assert info.mdb_name == "Bernd Schmidt"


def test_build_indexes_skips_constituency_with_no_mdbs() -> None:
    from meinimpact.infrastructure.mdb.wks_service import _WksRoot

    data = {
        "federalStates": [
            {
                "key": "XX",
                "name": "Test",
                "constituencies": [
                    {
                        "number": "1",
                        "name": "Empty",
                        "mdbs": [],
                        "counties": [
                            {
                                "headline": "X",
                                "communities": [
                                    {"name": "Town", "zipCodes": ["12345"]}
                                ],
                            }
                        ],
                    }
                ],
            }
        ]
    }
    root = _WksRoot.model_validate(data)
    plz_index, wk_index = _build_indexes(root)
    assert "12345" not in plz_index
    assert 1 not in wk_index


def test_build_indexes_deduplicates_plz_entries() -> None:
    from meinimpact.infrastructure.mdb.wks_service import _WksRoot

    data = {
        "federalStates": [
            {
                "key": "XX",
                "name": "Test",
                "constituencies": [
                    {
                        "number": "1",
                        "name": "Wahlkreis A",
                        "mdbs": [{"name": "A, B", "party": "SPD", "first": True}],
                        "counties": [
                            {
                                "headline": "X",
                                "communities": [
                                    {"name": "Town", "zipCodes": ["12345", "12345"]}
                                ],
                            }
                        ],
                    }
                ],
            }
        ]
    }
    root = _WksRoot.model_validate(data)
    plz_index, _ = _build_indexes(root)
    assert len(plz_index["12345"]) == 1


# ---------------------------------------------------------------------------
# _direktkandidat
# ---------------------------------------------------------------------------


def test_direktkandidat_returns_first_true() -> None:
    from meinimpact.infrastructure.mdb.wks_service import _MdbRecord

    mdbs = [
        _MdbRecord(name="A", party="X", first=False),
        _MdbRecord(name="B", party="X", first=True),
    ]
    result = _direktkandidat(mdbs)
    assert result is not None
    assert result.name == "B"


def test_direktkandidat_falls_back_to_first_entry() -> None:
    from meinimpact.infrastructure.mdb.wks_service import _MdbRecord

    mdbs = [
        _MdbRecord(name="A", party="X", first=False),
        _MdbRecord(name="B", party="X", first=False),
    ]
    result = _direktkandidat(mdbs)
    assert result is not None
    assert result.name == "A"


def test_direktkandidat_returns_none_for_empty_list() -> None:
    assert _direktkandidat([]) is None


# ---------------------------------------------------------------------------
# _format_name
# ---------------------------------------------------------------------------


def test_format_name_reverses_lastname_firstname() -> None:
    assert _format_name("Rentzsch, Matthias") == "Matthias Rentzsch"


def test_format_name_leaves_natural_order_unchanged() -> None:
    assert _format_name("Matthias Rentzsch") == "Matthias Rentzsch"
