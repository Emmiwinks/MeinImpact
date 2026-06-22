"""Tests for the Bundestag DIP API adapter.

Based on the real DIP OpenAPI spec v1.5. Key facts verified against it:
- Vorgang uses 'titel' (required), no 'betreff' field.
- f.vorgangstyp is a repeatable array param, not comma-separated.
- Cursor pagination stops when cursor stops changing (always present in response).
- There is no /abstimmung endpoint.
- API key always required.
"""

from datetime import date, datetime
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from meinimpact.infrastructure.sources.dip_adapter import (
    DipAdapter,
    _extract_initiative,
    _map_vorgangstyp,
    _parse_date,
    _parse_vorgang,
)

# ---------------------------------------------------------------------------
# Sample API response fixtures — matching real DIP Vorgang schema
# ---------------------------------------------------------------------------

_GESETZENTWURF_DOC = {
    "id": "270049",
    "typ": "Vorgang",
    "titel": "Entwurf eines Gesetzes zur Änderung des Klimaschutzgesetzes",
    "abstract": "Ausführliche Beschreibung des Gesetzentwurfs zur Klimapolitik.",
    "vorgangstyp": "Gesetzentwurf",
    "beratungsstand": "Dem Bundestag zugewiesen",
    "initiative": ["Bundesregierung"],
    "datum": "2024-01-15",
    "wahlperiode": 20,
    "aktualisiert": "2024-01-15T12:00:00+01:00",
}

_ANTRAG_DOC = {
    "id": "270050",
    "typ": "Vorgang",
    "titel": "Antrag zur Förderung erneuerbarer Energien",
    "vorgangstyp": "Antrag",
    "beratungsstand": "Überwiesen",
    "initiative": ["Fraktion der SPD", "Fraktion BÜNDNIS 90/DIE GRÜNEN"],
    "datum": "2024-01-14",
    "wahlperiode": 20,
    "aktualisiert": "2024-01-14T10:00:00+01:00",
}

_PETITION_DOC = {
    "id": "270051",
    "typ": "Vorgang",
    "titel": "Petition für mehr Klimaschutz",
    "vorgangstyp": "Petition",
    "beratungsstand": "Noch nicht beraten",
    "initiative": [],
    "datum": "2024-01-10",
    "wahlperiode": 20,
    "aktualisiert": "2024-01-10T09:00:00+01:00",
}

# Cursor values used in pagination tests
_CURSOR_A = "AoJwgNjC_PYCMURydWNrc2FjaGUtMjQ5MjYw"
_CURSOR_B = "BpKxhOkD_QZDNVSzeMTbLjYb3926o"


# ---------------------------------------------------------------------------
# HTTP mock helpers
# ---------------------------------------------------------------------------


def _make_response(json_body: object, status: int = 200) -> MagicMock:
    resp = MagicMock()
    resp.status_code = status
    resp.json = MagicMock(return_value=json_body)
    resp.raise_for_status = MagicMock()
    if status >= 400:
        resp.raise_for_status.side_effect = httpx.HTTPStatusError(
            f"HTTP {status}", request=MagicMock(), response=resp
        )
    return resp


def _make_client(side_effect: list[MagicMock]) -> AsyncMock:
    client = AsyncMock()
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    client.get = AsyncMock(side_effect=side_effect)
    return client


# ---------------------------------------------------------------------------
# fetch_new_items — happy path
# ---------------------------------------------------------------------------


async def test_fetch_new_items_returns_vorgaenge_and_petitionen() -> None:
    adapter = DipAdapter(api_key="test-key")
    responses = [
        # Vorgänge (Anträge + Gesetzentwürfe): single page, cursor unchanged
        _make_response(
            {"numFound": 2, "cursor": _CURSOR_A, "documents": [_GESETZENTWURF_DOC, _ANTRAG_DOC]}
        ),
        _make_response(
            {"numFound": 2, "cursor": _CURSOR_A, "documents": []}
        ),
        # Petitionen: single page, cursor unchanged
        _make_response(
            {"numFound": 1, "cursor": _CURSOR_B, "documents": [_PETITION_DOC]}
        ),
        _make_response(
            {"numFound": 1, "cursor": _CURSOR_B, "documents": []}
        ),
    ]
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=_make_client(responses),
    ):
        items = await adapter.fetch_new_items(datetime(2024, 1, 14))

    assert len(items) == 3
    types = {item["type"] for item in items}
    assert "gesetzentwurf" in types
    assert "antrag" in types
    assert "petition" in types


async def test_fetch_new_items_returns_empty_when_no_docs() -> None:
    adapter = DipAdapter(api_key="test-key")
    responses = [
        _make_response({"numFound": 0, "cursor": _CURSOR_A, "documents": []}),
        _make_response({"numFound": 0, "cursor": _CURSOR_A, "documents": []}),
        _make_response({"numFound": 0, "cursor": _CURSOR_B, "documents": []}),
        _make_response({"numFound": 0, "cursor": _CURSOR_B, "documents": []}),
    ]
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=_make_client(responses),
    ):
        items = await adapter.fetch_new_items(datetime(2024, 1, 14))

    assert items == []


# ---------------------------------------------------------------------------
# Cursor pagination — stops when cursor stops changing
# ---------------------------------------------------------------------------


async def test_fetch_paginated_follows_cursor_until_unchanged() -> None:
    """Pagination makes follow-up requests as long as cursor keeps changing."""
    adapter = DipAdapter(api_key="test-key")
    # Vorgänge: two pages (cursor changes once), then stops
    # Petitionen: single page
    responses = [
        _make_response(
            {"numFound": 2, "cursor": _CURSOR_A, "documents": [_GESETZENTWURF_DOC]}
        ),
        # Second request with cursor=_CURSOR_A → new cursor _CURSOR_B
        _make_response(
            {"numFound": 2, "cursor": _CURSOR_B, "documents": [_ANTRAG_DOC]}
        ),
        # Third request with cursor=_CURSOR_B → same cursor → stop
        _make_response(
            {"numFound": 2, "cursor": _CURSOR_B, "documents": []}
        ),
        # Petitionen: immediately stable cursor
        _make_response(
            {"numFound": 0, "cursor": _CURSOR_A, "documents": []}
        ),
        _make_response(
            {"numFound": 0, "cursor": _CURSOR_A, "documents": []}
        ),
    ]
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=_make_client(responses),
    ):
        items = await adapter.fetch_new_items(datetime(2024, 1, 14))

    assert len(items) == 2
    assert items[0]["external_id"] == "270049"
    assert items[1]["external_id"] == "270050"


# ---------------------------------------------------------------------------
# fetch_item_detail
# ---------------------------------------------------------------------------


async def test_fetch_item_detail_returns_parsed_vorgang() -> None:
    adapter = DipAdapter(api_key="test-key")
    client = _make_client([_make_response(_GESETZENTWURF_DOC)])
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        item = await adapter.fetch_item_detail("270049")

    assert item["external_id"] == "270049"
    assert item["type"] == "gesetzentwurf"
    assert item["source"] == "dip"


async def test_fetch_item_detail_raises_on_http_error() -> None:
    adapter = DipAdapter(api_key="test-key")
    client = _make_client([_make_response({}, status=404)])
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        with pytest.raises(httpx.HTTPStatusError):
            await adapter.fetch_item_detail("999")


async def test_fetch_new_items_raises_on_http_error() -> None:
    """Pipeline catches adapter exceptions; adapter propagates them."""
    adapter = DipAdapter(api_key="test-key")
    client = _make_client([_make_response({}, status=401)])
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        with pytest.raises(httpx.HTTPStatusError):
            await adapter.fetch_new_items(datetime(2024, 1, 14))


# ---------------------------------------------------------------------------
# _parse_vorgang — real schema field names
# ---------------------------------------------------------------------------


def test_parse_vorgang_uses_abstract_as_description() -> None:
    item = _parse_vorgang(_GESETZENTWURF_DOC)
    assert item["description"] == _GESETZENTWURF_DOC["abstract"]


def test_parse_vorgang_falls_back_to_titel_when_no_abstract() -> None:
    doc = {**_GESETZENTWURF_DOC}
    del doc["abstract"]
    item = _parse_vorgang(doc)
    assert item["description"] == _GESETZENTWURF_DOC["titel"]


def test_parse_vorgang_maps_all_fields() -> None:
    item = _parse_vorgang(_GESETZENTWURF_DOC)
    assert item["external_id"] == "270049"
    assert item["title"] == _GESETZENTWURF_DOC["titel"]
    assert item["type"] == "gesetzentwurf"
    assert item["status"] == "Dem Bundestag zugewiesen"
    assert item["deadline"] == date(2024, 1, 15)
    assert item["source_url"] == "https://dip.bundestag.de/vorgang/270049"
    assert item["initiated_by"] == "Bundesregierung"
    assert item["source"] == "dip"


def test_parse_vorgang_handles_missing_optional_fields() -> None:
    item = _parse_vorgang({"id": "1", "titel": "", "vorgangstyp": "", "wahlperiode": 20, "aktualisiert": ""})
    assert item["external_id"] == "1"
    assert item["title"] == ""
    assert item["description"] == ""
    assert item["status"] == ""
    assert item["deadline"] is None
    assert item["initiated_by"] == ""


def test_parse_vorgang_completely_empty_doc() -> None:
    item = _parse_vorgang({})
    assert item["external_id"] == ""
    assert item["title"] == ""


# ---------------------------------------------------------------------------
# _map_vorgangstyp
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("vorgangstyp", "expected"),
    [
        ("Gesetzentwurf", "gesetzentwurf"),
        ("gesetzentwurf", "gesetzentwurf"),
        ("Gesetzgebung", "gesetzentwurf"),
        ("Petition", "petition"),
        ("Öffentliche Petition", "petition"),
        ("Antrag", "antrag"),
        ("Anfrage", "antrag"),
        ("Geschäftsordnung", "antrag"),
        ("", "antrag"),
    ],
)
def test_map_vorgangstyp(vorgangstyp: str, expected: str) -> None:
    assert _map_vorgangstyp(vorgangstyp) == expected


# ---------------------------------------------------------------------------
# _parse_date
# ---------------------------------------------------------------------------


def test_parse_date_valid_iso() -> None:
    assert _parse_date("2024-01-15") == date(2024, 1, 15)


def test_parse_date_truncates_datetime_string() -> None:
    assert _parse_date("2024-01-15T12:00:00") == date(2024, 1, 15)


def test_parse_date_none_returns_none() -> None:
    assert _parse_date(None) is None


def test_parse_date_empty_string_returns_none() -> None:
    assert _parse_date("") is None


def test_parse_date_invalid_string_returns_none() -> None:
    assert _parse_date("not-a-date") is None


def test_parse_date_non_string_returns_none() -> None:
    assert _parse_date(20240115) is None  # type: ignore[arg-type]


# ---------------------------------------------------------------------------
# _extract_initiative
# ---------------------------------------------------------------------------


def test_extract_initiative_from_list() -> None:
    assert (
        _extract_initiative({"initiative": ["Fraktion der SPD", "Fraktion Grüne"]})
        == "Fraktion der SPD, Fraktion Grüne"
    )


def test_extract_initiative_single_item_list() -> None:
    assert _extract_initiative({"initiative": ["Bundesregierung"]}) == "Bundesregierung"


def test_extract_initiative_from_string() -> None:
    assert _extract_initiative({"initiative": "CDU/CSU"}) == "CDU/CSU"


def test_extract_initiative_empty_list() -> None:
    assert _extract_initiative({"initiative": []}) == ""


def test_extract_initiative_missing_key() -> None:
    assert _extract_initiative({}) == ""


def test_extract_initiative_filters_empty_entries() -> None:
    assert _extract_initiative({"initiative": ["SPD", "", "Grüne"]}) == "SPD, Grüne"
