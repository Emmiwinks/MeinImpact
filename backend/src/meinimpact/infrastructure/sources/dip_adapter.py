"""Bundestag DIP API adapter — Source 1 per specs/data/sources-federal.md.

Based on the official OpenAPI spec (v1.5):
  https://search.dip.bundestag.de/api/v1

Key API facts:
- API key always required (401 for all unauthenticated requests).
- f.vorgangstyp is a repeatable array param — must NOT be comma-separated.
- Cursor is always present in list responses; pagination stops when it stops changing.
- There is no /abstimmung endpoint; votes are tracked through Vorgänge.
- Vorgang uses 'titel' (not 'betreff') as its primary title field.
- Petition filter uses f.beratungsstand, not f.status.
"""

import logging
from datetime import date, datetime

import httpx

from meinimpact.infrastructure.sources.protocol import RawSourceItem

logger = logging.getLogger(__name__)

_BASE_URL = "https://search.dip.bundestag.de/api/v1"
_WEB_BASE = "https://dip.bundestag.de"
_PAGE_SIZE = 50


class DipAdapter:
    """Source adapter for the Bundestag DIP API v1."""

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]:
        """Fetches new Vorgänge (Gesetzentwürfe, Anträge) and open Petitionen."""
        since_date = since.date().isoformat()
        items: list[RawSourceItem] = []
        async with httpx.AsyncClient(timeout=30.0) as client:
            items.extend(await self._fetch_vorgaenge(client, since_date))
            items.extend(await self._fetch_petitionen(client))
        return items

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

        f.vorgangstyp and similar array filters must be passed as repeated
        key-value pairs, not comma-separated. Use extra_params as a list of
        tuples to support repeated keys.

        Pagination stops when the cursor returned by the API matches the
        cursor sent in the request (spec: "bis sich der cursor nicht mehr ändert").
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

            response = await client.get(f"{_BASE_URL}/{endpoint}", params=params)
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

    async def _fetch_vorgaenge(
        self, client: httpx.AsyncClient, since_date: str
    ) -> list[RawSourceItem]:
        # f.vorgangstyp is a repeatable array param — pass as two separate pairs
        docs = await self._fetch_paginated(
            client,
            "vorgang",
            [
                ("f.vorgangstyp", "Antrag"),
                ("f.vorgangstyp", "Gesetzentwurf"),
                ("f.datum.start", since_date),
            ],
        )
        return [_parse_vorgang(d) for d in docs]

    async def _fetch_petitionen(self, client: httpx.AsyncClient) -> list[RawSourceItem]:
        # f.beratungsstand is the correct filter (there is no f.status).
        # Sammelübersicht items are committee processing reports that bundle
        # already-closed petitions — not actionable for citizens, excluded here.
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
    """Maps a DIP Vorgang document to RawSourceItem.

    The Vorgang schema uses 'titel' (required) and 'abstract' (optional).
    There is no 'betreff' field.
    """
    external_id = str(doc.get("id") or "")
    vorgangstyp = str(doc.get("vorgangstyp") or "")
    title = " ".join(str(doc.get("titel") or "").split())
    description = " ".join(str(doc.get("abstract") or title).split())
    return RawSourceItem(
        external_id=external_id,
        title=title,
        type=_map_vorgangstyp(vorgangstyp),
        status=str(doc.get("beratungsstand") or ""),
        deadline=_parse_date(doc.get("datum")),
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
    """Extracts initiative as a comma-separated string."""
    raw = doc.get("initiative") or []
    if isinstance(raw, list):
        return ", ".join(str(i) for i in raw if i)
    return str(raw)
