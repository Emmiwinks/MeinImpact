"""Bundestag DIP API adapter — Source 1 per specs/data/sources-federal.md.

Based on the official OpenAPI spec (v1.5):
  https://search.dip.bundestag.de/api/v1

Key API facts:
- API key always required (401 for all unauthenticated requests).
- f.vorgangstyp and f.beratungsstand are repeatable array params —
  must NOT be comma-separated; pass as repeated key-value pairs.
- Cursor is always present in list responses; pagination stops when it stops changing.
- There is no /abstimmung endpoint; votes are tracked through Vorgänge.
- Vorgang uses 'titel' (not 'betreff') as its primary title field.
- f.datum.start filters by activity date (ISO date string). f.datum.start returns 400.
"""

import logging
from datetime import UTC, date, datetime, timedelta
from urllib.parse import quote, urlencode

import httpx

from meinimpact.infrastructure.sources.protocol import RawSourceItem

logger = logging.getLogger(__name__)

_BASE_URL = "https://search.dip.bundestag.de/api/v1"
_WEB_BASE = "https://dip.bundestag.de"
_PAGE_SIZE = 50

# Lookback window for the single-request Wahlperiode-resolution probe (see
# _resolve_current_wahlperiode) — recent enough to reliably catch the
# current legislative period, without being so wide it's likely to span a
# Wahlperiode change.
_WAHLPERIODE_PROBE_LOOKBACK_DAYS = 7

# Hard ceiling on pages per _fetch_paginated call, so a filter-value or
# scope mistake pages through DIP's entire history instead of failing fast.
_MAX_PAGES = 20


class DipAdapter:
    """Source adapter for the Bundestag DIP API v1.

    Fetches Vorgänge by vorgangstyp (Gesetzgebung, Antrag, Petition), not by
    beratungsstand or topic keywords — see `fetch_new_items` for why
    beratungsstand filtering happens downstream, in the state-rules engine,
    rather than in this adapter.
    """

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]:
        """Satisfies the `SourceAdapter` Protocol for Pipeline 1
        (parliamentary): every Gesetzgebung/Antrag Vorgang active since
        `since`, scoped to the current Wahlperiode. Excludes open
        petitions — see `fetch_open_petitions()` for Pipeline 2's
        Bundestag-petition-portal source.

        Deliberately does NOT filter by `beratungsstand`. That used to be
        a hardcoded allowlist of 4 stage strings (late-stage, committee,
        early-stage), which `scripts/audit_dip_coverage.py` showed was
        silently dropping real, active Vorgänge whose status wasn't one of
        those 4 — e.g. "Beschlussempfehlung liegt vor" (committee
        recommendation ready, vote imminent), Bundesrat-stage statuses on
        already-passed Gesetzgebung, and early "Antrag" motions still
        marked "Noch nicht beraten". The state-rules engine (see
        `state_rules/parliamentary_rules.py`), not this adapter, is
        responsible for deciding engagement state from the full status
        text — anything it doesn't recognise defaults to state D and is
        discarded downstream (`FilterStateDStep`), so fetching broadly here
        costs nothing but a few extra free API calls, and new
        `beratungsstand` wordings DIP introduces won't need an adapter
        change to be seen at all (only to be scored as A/B/C instead of the
        safe D default).

        Also note: the real API value is "Gesetzgebung", not
        "Gesetzentwurf" — `f.vorgangstyp=Gesetzentwurf` returns zero
        results against the live API (verified directly; an earlier,
        untested assumption used the wrong string).

        Any HTTP failure propagates as-is — the orchestrator aborts the
        whole run on any pipeline exception rather than persisting a
        partial pool as if nothing were wrong.
        """
        since_date = since.date().isoformat()
        async with httpx.AsyncClient(timeout=30.0) as client:
            wahlperiode = await self._resolve_current_wahlperiode(client)
            params: list[tuple[str, str | int]] = [
                ("f.vorgangstyp", "Gesetzgebung"),
                ("f.vorgangstyp", "Antrag"),
                ("f.datum.start", since_date),
            ]
            if wahlperiode is not None:
                params.append(("f.wahlperiode", wahlperiode))
            docs = await self._fetch_paginated(client, "vorgang", params)

        items: list[RawSourceItem] = []
        seen_urls: set[str] = set()
        for item in [_parse_vorgang(d) for d in docs]:
            if item["source_url"] not in seen_urls:
                items.append(item)
                seen_urls.add(item["source_url"])
        return items

    async def _resolve_current_wahlperiode(
        self, client: httpx.AsyncClient
    ) -> int | None:
        """Determines the current Bundestag legislative period from the
        single most recently updated Vorgang, so `fetch_new_items` can
        scope its broad query to it without a hardcoded period number that
        goes stale every ~4 years. `rows=1` keeps this a single bounded
        request, not a paginated one.

        Returns `None` if no recently updated Vorgang exists at all (e.g. a
        long recess) — callers then fall back to querying without a
        Wahlperiode filter, relying on `_MAX_PAGES` to still fail fast
        rather than hang if that turns out to be too broad.
        """
        since = (
            (datetime.now(UTC) - timedelta(days=_WAHLPERIODE_PROBE_LOOKBACK_DAYS))
            .date()
            .isoformat()
        )
        params: list[tuple[str, str | int]] = [
            ("apikey", self._api_key),
            ("format", "json"),
            ("rows", 1),
            ("f.datum.start", since),
        ]
        qs = urlencode(params, quote_via=quote)
        response = await client.get(f"{_BASE_URL}/vorgang?{qs}")
        response.raise_for_status()
        data: dict[str, object] = response.json()
        docs = data.get("documents") or []
        assert isinstance(docs, list)
        if not docs:
            logger.warning(
                "Could not resolve current Wahlperiode (no recently updated Vorgang) — "
                "fetch_new_items will run unscoped, relying on _MAX_PAGES as a bound."
            )
            return None
        wahlperiode = docs[0].get("wahlperiode")
        return wahlperiode if isinstance(wahlperiode, int) else None

    async def fetch_open_petitions(self) -> list[RawSourceItem]:
        """Pipeline 2 source: open Bundestag petitions from the petition
        portal (`f.vorgangstyp=Petition`)."""
        async with httpx.AsyncClient(timeout=30.0) as client:
            return await self._fetch_petitionen(client)

    async def fetch_item_detail(self, external_id: str) -> RawSourceItem:
        """Fetches a single Vorgang by its DIP numeric ID string."""
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.get(
                f"{_BASE_URL}/vorgang/{external_id}",
                params=self._base_params(),
            )
            response.raise_for_status()
        return _parse_vorgang(response.json())

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _base_params(self) -> dict[str, str]:
        return {"apikey": self._api_key, "format": "json"}

    async def _fetch_paginated(
        self,
        client: httpx.AsyncClient,
        endpoint: str,
        extra_params: list[tuple[str, str | int]],
    ) -> list[dict[str, object]]:
        """Fetches all pages from a DIP list endpoint.

        Array filters (f.beratungsstand, f.vorgangstyp) must be passed as
        repeated key-value pairs, not comma-separated.

        Pagination stops when the cursor returned by the API matches the
        cursor sent in the request, or after `_MAX_PAGES` pages — whichever
        comes first. Hitting the cap raises rather than silently truncating,
        since it means a filter is broader than intended.
        """
        all_docs: list[dict[str, object]] = []
        prev_cursor: str | None = None

        for _ in range(_MAX_PAGES):
            params: list[tuple[str, str | int]] = [
                ("apikey", self._api_key),
                ("format", "json"),
                ("rows", _PAGE_SIZE),
                *extra_params,
            ]
            if prev_cursor is not None:
                params.append(("cursor", prev_cursor))

            # Use quote (not quote_plus) so spaces encode as %20, not +.
            # The DIP API rejects + encoding in filter values.
            qs = urlencode(params, quote_via=quote)
            response = await client.get(f"{_BASE_URL}/{endpoint}?{qs}")
            response.raise_for_status()
            data: dict[str, object] = response.json()

            docs = data.get("documents") or []
            assert isinstance(docs, list)
            all_docs.extend(docs)

            new_cursor = data.get("cursor")
            assert isinstance(new_cursor, str)
            if new_cursor == prev_cursor:
                return all_docs
            prev_cursor = new_cursor

        raise RuntimeError(
            f"DIP {endpoint} query exceeded {_MAX_PAGES} pages without exhausting "
            f"its cursor (params={extra_params!r}) — filter is likely broader "
            "than intended rather than DIP legitimately having that much data."
        )

    async def _fetch_petitionen(self, client: httpx.AsyncClient) -> list[RawSourceItem]:
        """Pass C: Open Bundestag Petitionen (always included regardless of recency)."""
        docs = await self._fetch_paginated(
            client,
            "vorgang",
            [
                ("f.vorgangstyp", "Petition"),
                ("f.beratungsstand", "Noch nicht beraten"),
            ],
        )
        return [
            _parse_vorgang(d)
            for d in docs
            if not str(d.get("titel") or "").startswith("Sammelübersicht")
        ]


# ------------------------------------------------------------------
# Parsers (module-level for testability)
# ------------------------------------------------------------------


def _parse_vorgang(doc: dict[str, object]) -> RawSourceItem:
    """Maps a DIP Vorgang document to RawSourceItem."""
    external_id = str(doc.get("id") or "")
    vorgangstyp = str(doc.get("vorgangstyp") or "")
    beratungsstand = str(doc.get("beratungsstand") or "")
    title = " ".join(str(doc.get("titel") or "").split())
    description = " ".join(str(doc.get("abstract") or title).split())
    activity_date = _parse_date(doc.get("datum"))

    return RawSourceItem(
        external_id=external_id,
        title=title,
        type=_map_vorgangstyp(vorgangstyp),
        status=beratungsstand,
        deadline=activity_date,
        source_url=f"{_WEB_BASE}/vorgang/{external_id}",
        description=description,
        initiated_by=_extract_initiative(doc),
        source="dip",
    )


def _map_vorgangstyp(vorgangstyp: str) -> str:
    lower = vorgangstyp.lower()
    if "petition" in lower:
        return "petition"
    if "gesetzentwurf" in lower or "gesetzgebung" in lower:
        return "gesetzentwurf"
    return "antrag"


def _parse_date(value: object) -> date | None:
    if not value or not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value[:10])
    except ValueError:
        return None


def _extract_initiative(doc: dict[str, object]) -> str:
    raw = doc.get("initiative") or []
    if isinstance(raw, list):
        return ", ".join(str(i) for i in raw if i)
    return str(raw)


class DipPetitionAdapter:
    """Thin `SourceAdapter` wrapper exposing only `DipAdapter`'s Bundestag
    petition-portal fetch, for Pipeline 2 (petition, bottom-up). Pipeline 1
    uses `DipAdapter.fetch_new_items()` directly instead, which excludes
    petitions."""

    def __init__(self, dip_adapter: DipAdapter) -> None:
        self._dip = dip_adapter

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]:
        return await self._dip.fetch_open_petitions()

    async def fetch_item_detail(self, external_id: str) -> RawSourceItem:
        return await self._dip.fetch_item_detail(external_id)
