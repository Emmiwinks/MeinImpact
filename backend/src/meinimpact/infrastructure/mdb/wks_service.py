"""Bundestag WKS data service — PLZ to MdB lookup.

Primary source:  https://www.bundestag.de/static/appdata/filter/wks.json
  Maps ~6 800 of the ~8 300 German PLZs directly to their Wahlkreis/MdB.

Fallback source: Bundestag PLZ autocomplete endpoint
  Used for the ~17 % of valid PLZs not covered by the primary index
  (e.g. Dresden city-centre PLZs like 01097). The autocomplete returns
  a Wahlkreis number which is then resolved via a second in-memory index.
"""

import logging
import re
from dataclasses import dataclass

import httpx
from pydantic import BaseModel, ConfigDict, ValidationError

logger = logging.getLogger(__name__)

_WKS_URL = "https://www.bundestag.de/static/appdata/filter/wks.json"

# Bundestag PLZ autocomplete — returns {"results":[{"id":"159*~*01097", ...}]}
# The numeric prefix of "id" is the Wahlkreis number.
_AUTOCOMPLETE_URL = (
    "https://www.bundestag.de/ajax/filterlist/de/533302-533302/plz-ort-autocomplete"
)

_WK_ID_RE = re.compile(r"^(\d+)\*~\*")


# ---------------------------------------------------------------------------
# Pydantic models — extra='allow' so new fields added by Bundestag don't
# break validation; required fields are enforced by type annotations.
# ---------------------------------------------------------------------------


class _MdbRecord(BaseModel):
    model_config = ConfigDict(extra="allow")
    name: str
    party: str
    first: bool


class _CommunityRecord(BaseModel):
    model_config = ConfigDict(extra="allow")
    name: str
    zipCodes: list[str]


class _CountyRecord(BaseModel):
    model_config = ConfigDict(extra="allow")
    headline: str
    communities: list[_CommunityRecord]


class _ConstituencyRecord(BaseModel):
    model_config = ConfigDict(extra="allow")
    number: str  # JSON delivers this as a string, e.g. "258"
    name: str
    mdbs: list[_MdbRecord]
    counties: list[_CountyRecord]


class _FederalStateRecord(BaseModel):
    model_config = ConfigDict(extra="allow")
    key: str
    name: str
    constituencies: list[_ConstituencyRecord]


class _WksRoot(BaseModel):
    model_config = ConfigDict(extra="allow")
    federalStates: list[_FederalStateRecord]


# ---------------------------------------------------------------------------
# Public result type
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MdbInfo:
    """One candidate Wahlkreis/MdB match for a given PLZ."""

    wahlkreis_nr: int
    wahlkreis_name: str
    mdb_name: str  # formatted as "Firstname Lastname"
    mdb_party: str
    mdb_link: str | None


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------


class WksService:
    """Holds a loaded, indexed copy of the Bundestag WKS dataset."""

    def __init__(self) -> None:
        self._index: dict[str, list[MdbInfo]] = {}
        self._index_by_wk: dict[int, list[MdbInfo]] = {}
        self._load_error: str | None = None

    @property
    def is_healthy(self) -> bool:
        return self._load_error is None and bool(self._index)

    @property
    def load_error(self) -> str | None:
        return self._load_error

    async def load(self) -> None:
        """Download, validate, and index the WKS JSON."""
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(_WKS_URL)
        except httpx.RequestError as exc:
            msg = (
                f"CRITICAL ── WKS SERVICE UNAVAILABLE ──────────────────────\n"
                f"Could not reach {_WKS_URL}\n"
                f"Error: {exc}\n"
                f"The /mdb endpoint will return 503 until this is resolved.\n"
                f"────────────────────────────────────────────────────────────"
            )
            logger.critical(msg)
            self._load_error = str(exc)
            return

        if response.status_code != 200:
            msg = (
                f"CRITICAL ── WKS ENDPOINT RETURNED {response.status_code} ──\n"
                f"URL: {_WKS_URL}\n"
                f"The Bundestag may have moved this file. Check for a new URL.\n"
                f"The /mdb endpoint will return 503 until this is resolved.\n"
                f"────────────────────────────────────────────────────────────"
            )
            logger.critical(msg)
            self._load_error = f"HTTP {response.status_code}"
            return

        try:
            root = _WksRoot.model_validate(response.json())
        except (ValidationError, ValueError) as exc:
            msg = (
                f"CRITICAL ── WKS JSON FORMAT HAS CHANGED ────────────────────\n"
                f"URL: {_WKS_URL}\n"
                f"The Bundestag has changed the structure of the WKS dataset.\n"
                f"Update the Pydantic models in wks_service.py to match.\n"
                f"Validation errors:\n{exc}\n"
                f"The /mdb endpoint will return 503 until this is resolved.\n"
                f"────────────────────────────────────────────────────────────"
            )
            logger.critical(msg)
            self._load_error = f"JSON format changed: {exc}"
            return

        self._index, self._index_by_wk = _build_indexes(root)
        self._load_error = None
        logger.info(
            "WKS data loaded: %d PLZ entries, %d constituencies",
            len(self._index),
            sum(len(s.constituencies) for s in root.federalStates),
        )

    def lookup(self, plz: str) -> list[MdbInfo]:
        """Returns matching entries from the primary PLZ index (fast, in-memory)."""
        return self._index.get(plz.strip(), [])

    async def lookup_with_fallback(self, plz: str) -> list[MdbInfo]:
        """Looks up a PLZ, falling back to the Bundestag autocomplete API.

        The primary WKS index covers ~83 % of German PLZs. For the rest
        (e.g. Dresden city PLZs like 01097) this method calls the autocomplete
        endpoint to retrieve the Wahlkreis number, then resolves via the
        Wahlkreis index.
        """
        plz = plz.strip()
        results = self._index.get(plz, [])
        if results:
            return results

        wk_nr = await self._autocomplete_wahlkreis(plz)
        if wk_nr is None:
            return []
        return self._index_by_wk.get(wk_nr, [])

    async def _autocomplete_wahlkreis(self, plz: str) -> int | None:
        """Calls the Bundestag PLZ autocomplete and extracts the Wahlkreis number."""
        try:
            async with httpx.AsyncClient(timeout=8.0) as client:
                response = await client.get(_AUTOCOMPLETE_URL, params={"q": plz})
        except httpx.RequestError as exc:
            logger.warning("PLZ autocomplete request failed for %s: %s", plz, exc)
            return None

        if response.status_code != 200:
            logger.warning(
                "PLZ autocomplete returned HTTP %d for %s",
                response.status_code,
                plz,
            )
            return None

        try:
            data = response.json()
        except ValueError:
            return None

        for result in data.get("results", []):
            m = _WK_ID_RE.match(result.get("id", ""))
            if m:
                return int(m.group(1))
        return None


# ---------------------------------------------------------------------------
# Index builders
# ---------------------------------------------------------------------------


def _build_indexes(
    root: _WksRoot,
) -> tuple[dict[str, list[MdbInfo]], dict[int, list[MdbInfo]]]:
    """Builds both the PLZ index and the Wahlkreis-number index."""
    plz_index: dict[str, list[MdbInfo]] = {}
    wk_index: dict[int, list[MdbInfo]] = {}

    for state in root.federalStates:
        for constituency in state.constituencies:
            mdb = _direktkandidat(constituency.mdbs)
            if mdb is None:
                continue
            info = MdbInfo(
                wahlkreis_nr=int(constituency.number),
                wahlkreis_name=constituency.name,
                mdb_name=_format_name(mdb.name),
                mdb_party=mdb.party,
                mdb_link=getattr(mdb, "link", None),
            )
            wk_index[info.wahlkreis_nr] = [info]
            for county in constituency.counties:
                for community in county.communities:
                    for plz in community.zipCodes:
                        existing = plz_index.setdefault(plz, [])
                        if not any(
                            e.wahlkreis_nr == info.wahlkreis_nr for e in existing
                        ):
                            existing.append(info)

    return plz_index, wk_index


def _direktkandidat(mdbs: list[_MdbRecord]) -> _MdbRecord | None:
    """Returns the direct mandate winner (first=True), or the first MdB as fallback."""
    for mdb in mdbs:
        if mdb.first:
            return mdb
    return mdbs[0] if mdbs else None


def _format_name(name: str) -> str:
    """Converts 'Lastname, Firstname' → 'Firstname Lastname'."""
    if "," in name:
        last, _, first = name.partition(",")
        return f"{first.strip()} {last.strip()}"
    return name
