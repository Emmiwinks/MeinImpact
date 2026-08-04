"""Tests for the Bundestag DIP API adapter.

Based on the real DIP OpenAPI spec v1.5. Key facts verified against it:
- Vorgang uses 'titel' (required), no 'betreff' field.
- f.vorgangstyp is a repeatable array param, not comma-separated.
- Cursor pagination stops when cursor stops changing (always present in response).
- There is no /abstimmung endpoint.
- API key always required.
- The real vorgangstyp value for bills is "Gesetzgebung", not
  "Gesetzentwurf" — verified directly against the live API
  (f.vorgangstyp=Gesetzentwurf returns zero results). See
  scripts/audit_dip_coverage.py.
"""

from datetime import date, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from meinimpact.infrastructure.sources.dip_adapter import (
    DipAdapter,
    DipPetitionAdapter,
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
    "vorgangstyp": "Gesetzgebung",
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
# URL encoding — spaces must be %20, not +
# ---------------------------------------------------------------------------


async def test_fetch_open_petitions_request_url_uses_percent_encoding() -> None:
    """DIP API rejects + encoding in filter values; spaces must appear as %20.

    This test captures the actual URL string passed to client.get() and
    asserts that the (multi-word) beratungsstand filter value uses %20, not
    +. It would have caught the encoding bug discovered when first running
    the pipeline live.
    """
    adapter = DipAdapter(api_key="test-key")
    captured: list[str] = []

    async def _capturing_get(url: str, **_: object) -> MagicMock:
        captured.append(url)
        return _make_response({"numFound": 0, "cursor": _CURSOR_A, "documents": []})

    client = MagicMock()
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    client.get = _capturing_get

    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        await adapter.fetch_open_petitions()

    beratungsstand_urls = [u for u in captured if "beratungsstand" in u]
    assert beratungsstand_urls, "Expected at least one request with f.beratungsstand"

    for url in beratungsstand_urls:
        assert "%20" in url, f"Expected %20 encoding for multi-word value in: {url}"
        assert "+" not in url, f"Found + encoding in: {url}"
        assert " " not in url, f"Found unencoded space in: {url}"


# ---------------------------------------------------------------------------
# fetch_open_petitions — Pipeline 2's Bundestag-petition-portal source
# ---------------------------------------------------------------------------


async def test_fetch_open_petitions_returns_parsed_petitions() -> None:
    adapter = DipAdapter(api_key="test-key")
    responses = [
        _make_response(
            {"numFound": 1, "cursor": _CURSOR_A, "documents": [_PETITION_DOC]}
        ),
        _make_response({"numFound": 1, "cursor": _CURSOR_A, "documents": []}),
    ]
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=_make_client(responses),
    ):
        items = await adapter.fetch_open_petitions()

    assert len(items) == 1
    assert items[0]["external_id"] == "270051"
    assert items[0]["type"] == "petition"


async def test_fetch_open_petitions_filters_out_sammeluebersicht() -> None:
    """Sammelübersicht Vorgänge bundle many petitions' decisions into one
    administrative summary item — not a petition citizens can act on, so
    it's excluded even though it matches the same vorgangstyp/beratungsstand
    filter as a real open petition."""
    adapter = DipAdapter(api_key="test-key")
    sammeluebersicht_doc = {
        **_PETITION_DOC,
        "id": "999999",
        "titel": "Sammelübersicht 123 zu Petitionen",
    }
    responses = [
        _make_response(
            {
                "numFound": 2,
                "cursor": _CURSOR_A,
                "documents": [_PETITION_DOC, sammeluebersicht_doc],
            }
        ),
        _make_response({"numFound": 2, "cursor": _CURSOR_A, "documents": []}),
    ]
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=_make_client(responses),
    ):
        items = await adapter.fetch_open_petitions()

    assert len(items) == 1
    assert items[0]["external_id"] == "270051"


# ---------------------------------------------------------------------------
# fetch_new_items — Pipeline 1's entry point: one broad fetch by vorgangstyp
# (Gesetzgebung, Antrag), scoped by wahlperiode + `since`, with NO
# beratungsstand filter — engagement state is decided downstream by the
# state-rules engine, not by narrowing the DIP query itself. See
# scripts/audit_dip_coverage.py for why the old hardcoded-stage-allowlist
# approach was silently dropping real Vorgänge.
# ---------------------------------------------------------------------------


async def test_fetch_new_items_broad_fetch_no_beratungsstand_filter() -> None:
    """The broad fetch must filter only by vorgangstyp and date/wahlperiode
    — never by beratungsstand. Also verifies the real API vorgangstyp value
    is "Gesetzgebung", not "Gesetzentwurf" (confirmed against the live API:
    f.vorgangstyp=Gesetzentwurf returns zero results)."""
    adapter = DipAdapter(api_key="test-key")
    responses = [
        # Wahlperiode-resolution probe (rows=1, single request, not paginated)
        _make_response(
            {"numFound": 1, "cursor": _CURSOR_A, "documents": [_ANTRAG_DOC]}
        ),
        # Broad fetch: one page, cursor stable
        _make_response(
            {
                "numFound": 2,
                "cursor": _CURSOR_B,
                "documents": [_GESETZENTWURF_DOC, _ANTRAG_DOC],
            }
        ),
        _make_response({"numFound": 2, "cursor": _CURSOR_B, "documents": []}),
    ]
    captured: list[str] = []

    async def _capturing_get(url: str, **_: object) -> MagicMock:
        captured.append(url)
        return responses.pop(0)

    client = MagicMock()
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    client.get = _capturing_get

    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        items = await adapter.fetch_new_items(datetime(2024, 1, 20))

    assert len(items) == 2
    types = {item["type"] for item in items}
    assert types == {"gesetzentwurf", "antrag"}

    broad_urls = [u for u in captured if "f.vorgangstyp=Gesetzgebung" in u]
    assert broad_urls, "Expected a request filtering on f.vorgangstyp=Gesetzgebung"
    for url in broad_urls:
        assert "f.vorgangstyp=Antrag" in url
        assert "f.beratungsstand" not in url
        assert "f.datum.start=2024-01-20" in url
        assert "f.wahlperiode=20" in url


async def test_fetch_new_items_omits_wahlperiode_filter_when_unresolved() -> None:
    """Falls back to an unscoped query (bounded by _MAX_PAGES) rather than
    guessing or failing outright when the wahlperiode probe finds nothing
    recent."""
    adapter = DipAdapter(api_key="test-key")
    responses = [
        _make_response({"numFound": 0, "cursor": _CURSOR_A, "documents": []}),
        _make_response({"numFound": 0, "cursor": _CURSOR_B, "documents": []}),
        _make_response({"numFound": 0, "cursor": _CURSOR_B, "documents": []}),
    ]
    captured: list[str] = []

    async def _capturing_get(url: str, **_: object) -> MagicMock:
        captured.append(url)
        return responses.pop(0)

    client = MagicMock()
    client.__aenter__ = AsyncMock(return_value=client)
    client.__aexit__ = AsyncMock(return_value=False)
    client.get = _capturing_get

    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=client,
    ):
        await adapter.fetch_new_items(datetime(2024, 1, 20))

    assert captured, "Expected at least one request"
    assert all("f.wahlperiode" not in u for u in captured)


async def test_resolve_current_wahlperiode_reads_field_from_most_recent_vorgang() -> None:
    """No hardcoded legislative-period number — it's read off whatever
    DIP itself says is currently active, from a single rows=1 probe."""
    adapter = DipAdapter(api_key="test-key")
    client = _make_client(
        [_make_response({"numFound": 1, "cursor": _CURSOR_A, "documents": [_ANTRAG_DOC]})]
    )
    wahlperiode = await adapter._resolve_current_wahlperiode(client)

    assert wahlperiode == 20


async def test_resolve_current_wahlperiode_returns_none_when_nothing_recent() -> None:
    adapter = DipAdapter(api_key="test-key")
    client = _make_client([_make_response({"numFound": 0, "cursor": _CURSOR_A, "documents": []})])
    wahlperiode = await adapter._resolve_current_wahlperiode(client)

    assert wahlperiode is None


async def test_fetch_new_items_raises_on_http_failure() -> None:
    """DIP is Pipeline 1's only source — an HTTP failure must propagate
    (not be swallowed into an empty list), so the orchestrator's
    fail-loud `asyncio.gather` (no `return_exceptions`) aborts the whole
    run instead of persisting a parliamentary-empty pool as if nothing
    were wrong."""
    adapter = DipAdapter(api_key="test-key")
    client = _make_client([_make_response({}, status=500)])
    with (
        patch(
            "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
            return_value=client,
        ),
        pytest.raises(httpx.HTTPStatusError),
    ):
        await adapter.fetch_new_items(datetime.now())


async def test_fetch_open_petitions_raises_on_http_failure() -> None:
    adapter = DipAdapter(api_key="test-key")
    client = _make_client([_make_response({}, status=500)])
    with (
        patch(
            "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
            return_value=client,
        ),
        pytest.raises(httpx.HTTPStatusError),
    ):
        await adapter.fetch_open_petitions()


async def test_dip_petition_adapter_propagates_http_failure() -> None:
    dip = DipAdapter(api_key="test-key")
    client = _make_client([_make_response({}, status=500)])
    adapter = DipPetitionAdapter(dip)
    with (
        patch(
            "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
            return_value=client,
        ),
        pytest.raises(httpx.HTTPStatusError),
    ):
        await adapter.fetch_new_items(datetime.now())


# ---------------------------------------------------------------------------
# Cursor pagination — stops when cursor stops changing
# ---------------------------------------------------------------------------


async def test_fetch_paginated_follows_cursor_until_unchanged() -> None:
    """Pagination makes follow-up requests as long as cursor keeps changing."""
    adapter = DipAdapter(api_key="test-key")
    responses = [
        # Wahlperiode-resolution probe (rows=1, single request)
        _make_response(
            {"numFound": 1, "cursor": _CURSOR_A, "documents": [_ANTRAG_DOC]}
        ),
        # Broad fetch: two pages (cursor changes once then stops)
        _make_response(
            {"numFound": 2, "cursor": _CURSOR_A, "documents": [_GESETZENTWURF_DOC]}
        ),
        _make_response(
            {"numFound": 2, "cursor": _CURSOR_B, "documents": [_ANTRAG_DOC]}
        ),
        _make_response({"numFound": 2, "cursor": _CURSOR_B, "documents": []}),
    ]
    with patch(
        "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
        return_value=_make_client(responses),
    ):
        items = await adapter.fetch_new_items(datetime(2024, 1, 20))

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
    with (
        patch(
            "meinimpact.infrastructure.sources.dip_adapter.httpx.AsyncClient",
            return_value=client,
        ),
        pytest.raises(httpx.HTTPStatusError),
    ):
        await adapter.fetch_item_detail("999")


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
    item = _parse_vorgang(
        {
            "id": "1",
            "titel": "",
            "vorgangstyp": "",
            "wahlperiode": 20,
            "aktualisiert": "",
        }
    )
    item = _parse_vorgang(
        {
            "id": "1",
            "titel": "",
            "vorgangstyp": "",
            "wahlperiode": 20,
            "aktualisiert": "",
        }
    )
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
    assert _parse_date(20240115) is None


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


# ---------------------------------------------------------------------------
# Live integration test — excluded from default CI run (-m 'not live')
# Run manually: pytest -m live tests/test_dip_adapter.py
# ---------------------------------------------------------------------------


@pytest.mark.live
async def test_fetch_hot_items_live_response_shape() -> None:
    """Hits the real DIP API and validates the response contract.

    Run with: docker compose exec api python -m pytest -m live tests/test_dip_adapter.py

    Catches:
    - API endpoint changes (URL, auth, param names)
    - Field renames in the Vorgang schema
    - beratungsstand value changes that would silently return 0 results
    - URL encoding issues (the + vs %20 class of bug)
    """
    from meinimpact.core.config import Settings

    settings = Settings()
    if not settings.dip_api_key:
        pytest.skip("MEINIMPACT_DIP_API_KEY not set")

    adapter = DipAdapter(api_key=settings.dip_api_key)
    items = await adapter.fetch_hot_items()

    assert isinstance(items, list), "fetch_hot_items must return a list"
    assert len(items) > 0, (
        "Expected at least one hot item — if Bundestag is in recess this may "
        "legitimately be empty; verify manually."
    )

    for item in items:
        assert item["external_id"], "external_id must be non-empty"
        assert item["title"], "title must be non-empty"
        assert item["source"] == "dip"
        assert item["source_url"].startswith("https://dip.bundestag.de/vorgang/")
        assert 0.0 <= item["imminence_score"] <= 1.0
        assert item["type"] in {"gesetzentwurf", "antrag", "petition"}


@pytest.mark.live
async def test_fetch_new_items_live_response_shape() -> None:
    """Hits the real DIP API via the broad (no-beratungsstand-filter) query
    used by Pipeline 1 and checks it actually surfaces the stages the old
    hardcoded allowlist was missing (see scripts/audit_dip_coverage.py):
    Beschlussempfehlung liegt vor, Bundesrat-stage Gesetzgebung, and
    "Noch nicht beraten" Antrag. Not asserted as a hard requirement (DIP's
    recess schedule varies) — logged instead so a run can be eyeballed.

    Run with: docker compose exec api python -m pytest -m live tests/test_dip_adapter.py
    """
    from meinimpact.core.config import Settings

    settings = Settings()
    if not settings.dip_api_key:
        pytest.skip("MEINIMPACT_DIP_API_KEY not set")

    adapter = DipAdapter(api_key=settings.dip_api_key)
    items = await adapter.fetch_new_items(datetime.now() - timedelta(days=14))

    assert isinstance(items, list), "fetch_new_items must return a list"
    assert len(items) > 0, (
        "Expected at least one item — if Bundestag is in recess this may "
        "legitimately be empty; verify manually."
    )

    for item in items:
        assert item["external_id"], "external_id must be non-empty"
        assert item["title"], "title must be non-empty"
        assert item["source"] == "dip"
        assert item["type"] in {"gesetzentwurf", "antrag"}

    statuses = {item["status"] for item in items}
    print(f"\nfetch_new_items returned {len(items)} items across statuses: {statuses}")
