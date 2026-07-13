"""Bundestag.de MdB RSS position check — MdB-position source 3.

Per specs/data/sources-federal.md "Source 6: MdB Public Statements".
Parses title/pubDate only, no full text needed. Per spec, only articles from
the last 60 days count regardless of the caller's `since` — this adapter
clamps to whichever cutoff is more recent.
"""

import logging
from datetime import datetime, timedelta
from email.utils import parsedate_to_datetime
from xml.etree import ElementTree

import httpx

from meinimpact.infrastructure.sources.protocol import MdbTarget, PositionCheckResult

logger = logging.getLogger(__name__)

_BASE_URL = "https://www.bundestag.de/ajax/filterlist/de/abgeordnete"
_SOURCE_NAME = "bundestag_rss"
_LOOKBACK_DAYS = 60


class BundestagRssPositionAdapter:
    """Checks the MdB's Bundestag.de RSS feed for a matching recent article.

    URL naming convention ({nachname}-{vorname}) is not guaranteed for all
    MdBs (see specs/data/sources-federal.md Open Questions) — a lookup
    fallback may be needed once verified against live data.
    """

    async def check_position(
        self, mdb: MdbTarget, descriptors: list[str], since: datetime
    ) -> PositionCheckResult:
        if not mdb.nachname or not mdb.vorname:
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        slug = f"{mdb.nachname}-{mdb.vorname}"
        url = f"{_BASE_URL}/{slug}/rss"
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(url)
                response.raise_for_status()
            entries = _parse_rss(response.text)
        except Exception as exc:
            logger.warning("Bundestag RSS check failed for %s: %s", mdb.name, exc)
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        max_lookback = datetime.now() - timedelta(days=_LOOKBACK_DAYS)
        cutoff_date = max(since.date(), max_lookback.date())
        match = _find_matching_entry(entries, descriptors, cutoff_date)
        if match is None:
            return PositionCheckResult(found=False, source=_SOURCE_NAME)

        return PositionCheckResult(
            found=True,
            source=_SOURCE_NAME,
            statement_summary=match["title"][:500],
            source_url=match.get("link") or None,
        )


def _parse_rss(xml_text: str) -> list[dict[str, str]]:
    root = ElementTree.fromstring(xml_text)
    entries: list[dict[str, str]] = []
    for item in root.findall(".//item"):
        entries.append(
            {
                "title": item.findtext("title") or "",
                "link": item.findtext("link") or "",
                "pubDate": item.findtext("pubDate") or "",
            }
        )
    return entries


def _find_matching_entry(
    entries: list[dict[str, str]],
    descriptors: list[str],
    cutoff_date: object,
) -> dict[str, str] | None:
    lowered = [d.lower() for d in descriptors]
    for entry in entries:
        title_lower = entry["title"].lower()
        if not any(d in title_lower for d in lowered):
            continue
        pub_date = _parse_pub_date(entry["pubDate"])
        if pub_date is not None and pub_date.date() < cutoff_date:  # type: ignore[operator]
            continue
        return entry
    return None


def _parse_pub_date(value: str) -> datetime | None:
    if not value:
        return None
    try:
        return parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
