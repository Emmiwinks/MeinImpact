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

# Imminence scores by beratungsstand stage.
# Higher = decision is closer / citizen action is more time-sensitive.
BERATUNGSSTAND_SCORE: dict[str, float] = {
    "2. Beratung und Schlussabstimmung": 1.0,
    "3. Beratung": 1.0,
    "2. Beratung": 0.8,
    "Ausschussberatung": 0.5,
}

# How many days back each pass looks for recent activity.
_LATE_STAGE_LOOKBACK_DAYS = 7
_COMMITTEE_LOOKBACK_DAYS = 3


class DipAdapter:
    """Source adapter for the Bundestag DIP API v1.

    Fetches Vorgänge by beratungsstand stage rather than by topic keywords.
    Hotness is determined by parliamentary process stage and recency.
    """

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def fetch_hot_items(self) -> list[RawSourceItem]:
        """Fetches Vorgänge in active deliberation stages + open Petitionen.

        Three passes:
        - Pass A: late-stage (2./3. Beratung) updated in last 7 days
        - Pass B: committee deliberation updated in last 3 days
        - Pass C: open Bundestag Petitionen (always included)

        Each item receives an imminence_score based on stage and recency.
        """
        items: list[RawSourceItem] = []
        seen_urls: set[str] = set()

        async with httpx.AsyncClient(timeout=30.0) as client:
            for item in await self._fetch_late_stage(client):
                if item["source_url"] not in seen_urls:
                    items.append(item)
                    seen_urls.add(item["source_url"])

            for item in await self._fetch_committee_stage(client):
                if item["source_url"] not in seen_urls:
                    items.append(item)
                    seen_urls.add(item["source_url"])

            for item in await self._fetch_petitionen(client):
                if item["source_url"] not in seen_urls:
                    items.append(item)
                    seen_urls.add(item["source_url"])

        logger.info("DIP fetch: %d hot items total", len(items))
        return items

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]:
        """Satisfies the `SourceAdapter` Protocol for Pipeline 1
        (parliamentary): late-stage + committee-deliberation Vorgänge only.
        Excludes open petitions — see `fetch_open_petitions()` for Pipeline
        2's Bundestag-petition-portal source.

        `since` is currently unused; each pass uses its own fixed lookback
        window (see `_LATE_STAGE_LOOKBACK_DAYS` / `_COMMITTEE_LOOKBACK_DAYS`),
        matching `fetch_hot_items()`'s existing behaviour.
        """
        items: list[RawSourceItem] = []
        seen_urls: set[str] = set()
        async with httpx.AsyncClient(timeout=30.0) as client:
            for item in await self._fetch_late_stage(client):
                if item["source_url"] not in seen_urls:
                    items.append(item)
                    seen_urls.add(item["source_url"])
            for item in await self._fetch_committee_stage(client):
                if item["source_url"] not in seen_urls:
                    items.append(item)
                    seen_urls.add(item["source_url"])
        return items

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
        extra_params: list[tuple[str, str]],
    ) -> list[dict[str, object]]:
        """Fetches all pages from a DIP list endpoint.

        Array filters (f.beratungsstand, f.vorgangstyp) must be passed as
        repeated key-value pairs, not comma-separated.

        Pagination stops when the cursor returned by the API matches the
        cursor sent in the request.
        """
        all_docs: list[dict[str, object]] = []
        prev_cursor: str | None = None

        while True:
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
                break
            prev_cursor = new_cursor

        return all_docs

    async def _fetch_late_stage(self, client: httpx.AsyncClient) -> list[RawSourceItem]:
        """Pass A: Vorgänge in 2./3. Beratung updated in the last 7 days."""
        since = (datetime.now(UTC) - timedelta(days=_LATE_STAGE_LOOKBACK_DAYS)).date().isoformat()
        docs = await self._fetch_paginated(
            client,
            "vorgang",
            [
                ("f.beratungsstand", "2. Beratung und Schlussabstimmung"),
                ("f.beratungsstand", "3. Beratung"),
                ("f.beratungsstand", "2. Beratung"),
                ("f.datum.start", since),
            ],
        )
        return [_parse_vorgang(d) for d in docs]

    async def _fetch_committee_stage(self, client: httpx.AsyncClient) -> list[RawSourceItem]:
        """Pass B: Vorgänge in Ausschussberatung updated in the last 3 days."""
        since = (datetime.now(UTC) - timedelta(days=_COMMITTEE_LOOKBACK_DAYS)).date().isoformat()
        docs = await self._fetch_paginated(
            client,
            "vorgang",
            [
                ("f.beratungsstand", "Ausschussberatung"),
                ("f.datum.start", since),
            ],
        )
        return [_parse_vorgang(d) for d in docs]

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
# Parsers and scoring (module-level for testability)
# ------------------------------------------------------------------


def _parse_vorgang(doc: dict[str, object]) -> RawSourceItem:
    """Maps a DIP Vorgang document to RawSourceItem with imminence_score."""
    external_id = str(doc.get("id") or "")
    vorgangstyp = str(doc.get("vorgangstyp") or "")
    beratungsstand = str(doc.get("beratungsstand") or "")
    title = " ".join(str(doc.get("titel") or "").split())
    description = " ".join(str(doc.get("abstract") or title).split())
    activity_date = _parse_date(doc.get("datum"))

    imminence = calculate_imminence(beratungsstand, activity_date)

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
        imminence_score=imminence,
    )


def calculate_imminence(beratungsstand: str, activity_date: date | None) -> float:
    """Computes a 0.0–1.0 imminence score from stage and recency.

    Stage weight: 0.7 — how close the item is to a final parliamentary decision.
    Recency weight: 0.3 — how recently there was activity (7-day window).
    """
    stage_score = BERATUNGSSTAND_SCORE.get(beratungsstand, 0.3)

    if activity_date is not None:
        days_ago = (date.today() - activity_date).days
        recency_score = max(0.0, 1.0 - days_ago / 7.0)
    else:
        recency_score = 0.5

    return stage_score * 0.7 + recency_score * 0.3


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

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]:  # noqa: ARG002
        return await self._dip.fetch_open_petitions()

    async def fetch_item_detail(self, external_id: str) -> RawSourceItem:
        return await self._dip.fetch_item_detail(external_id)
