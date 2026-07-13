"""DIP Plenarprotokolle (Reden) position check — MdB-position source 2.

Per specs/data/sources-federal.md "Source 6: MdB Public Statements".
Requires the MdB's DIP person ID (distinct from the Abgeordnetenwatch ID),
resolved via `mdb/mdb_id_resolution.py`.
"""

import logging
from datetime import datetime
from urllib.parse import quote, urlencode

import httpx

from meinimpact.infrastructure.sources.protocol import MdbTarget, PositionCheckResult

logger = logging.getLogger(__name__)

_BASE_URL = "https://search.dip.bundestag.de/api/v1"
_SOURCE_NAME = "dip_reden"


class DipRedenPositionAdapter:
    """Checks DIP /aktivitaet for a Rede by the MdB matching the action's
    descriptors (DIP Sachgebiet/Deskriptor tags)."""

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def check_position(
        self, mdb: MdbTarget, descriptors: list[str], since: datetime
    ) -> PositionCheckResult:
        if mdb.dip_person_id is None:
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        params = [
            ("apikey", self._api_key),
            ("format", "json"),
            ("f.person.id", mdb.dip_person_id),
            ("f.aktivitaetsart", "Rede"),
            ("f.datum.start", since.date().isoformat()),
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
            logger.warning("DIP Reden position check failed for %s: %s", mdb.name, exc)
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        documents = data.get("documents") or []
        if not isinstance(documents, list):
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        match = _find_matching_rede(documents, descriptors)
        if match is None:
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        return PositionCheckResult(
            found=True,
            source=_SOURCE_NAME,
            statement_summary=str(match.get("titel", ""))[:500],
            source_url=f"https://dip.bundestag.de/aktivitaet/{match.get('id', '')}",
        )


def _find_matching_rede(
    documents: list[object], descriptors: list[str]
) -> dict[str, object] | None:
    lowered = {d.lower() for d in descriptors}
    for doc in documents:
        if not isinstance(doc, dict):
            continue
        deskriptoren = doc.get("deskriptor") or []
        if not isinstance(deskriptoren, list):
            continue
        names = {
            str(d.get("name", "")).lower() for d in deskriptoren if isinstance(d, dict)
        }
        if names & lowered:
            return doc
    return None
