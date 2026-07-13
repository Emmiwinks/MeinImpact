"""DIP committee-activity check — state A trigger #2.

Per specs/data/ingestion-pipeline.md "State Determination: Parliamentary
Actions": a Vorgang in Ausschussberatung is state A only if the responsible
committee has met recently. Endpoint/filter values are best-guess per
specs/data/sources-federal.md Open Questions (the controlled vocabulary for
DIP's /aktivitaet filters is not published) — verify against live API data.
"""

import logging
from datetime import date
from urllib.parse import quote, urlencode

import httpx

logger = logging.getLogger(__name__)

_BASE_URL = "https://search.dip.bundestag.de/api/v1"
_COMMITTEE_ACTIVITY_TYPE = "Ausschusssitzung"


class DipCommitteeActivityAdapter:
    """Checks DIP /aktivitaet for a recent Ausschuss-Sitzung on a Vorgang."""

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def has_recent_activity(self, vorgang_id: str, since: date) -> bool:
        """Returns True if the committee met on or after `since`."""
        params = [
            ("apikey", self._api_key),
            ("format", "json"),
            ("f.vorgangsbezug.id", vorgang_id),
            ("f.aktivitaetsart", _COMMITTEE_ACTIVITY_TYPE),
            ("f.datum.start", since.isoformat()),
        ]
        # Use quote (not quote_plus) so spaces encode as %20, not + —
        # DIP rejects + encoding in filter values (see dip_adapter.py).
        qs = urlencode(params, quote_via=quote)
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(f"{_BASE_URL}/aktivitaet?{qs}")
                response.raise_for_status()
            data: dict[str, object] = response.json()
        except Exception as exc:
            logger.warning(
                "DIP committee-activity check failed for Vorgang %s: %s",
                vorgang_id,
                exc,
            )
            return False

        documents = data.get("documents") or []
        return isinstance(documents, list) and len(documents) > 0
