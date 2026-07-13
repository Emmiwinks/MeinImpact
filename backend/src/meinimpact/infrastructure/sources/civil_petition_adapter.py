"""Civil-society petition source — Pipeline 2 (petition, bottom-up).

Per specs/data/sources-federal.md "Source 4: Civil Society Petitions".
Primary: Tavily domain-restricted search on WeAct + openpetition.
Fallback: Google Custom Search, only when Tavily returns no results.

This extracts the Tavily petition-search logic that previously lived inline
in `pipeline/orchestrator.py` (`_fetch_civil_petitions`), and adds the
Google CSE fallback described in the spec but not previously implemented.
"""

import logging
from datetime import datetime
from urllib.parse import urlparse

from meinimpact.infrastructure.sources.google_cse_adapter import GoogleCseAdapter
from meinimpact.infrastructure.sources.protocol import RawSourceItem
from meinimpact.infrastructure.sources.tavily_client import TavilyClient

logger = logging.getLogger(__name__)

_PETITION_DOMAINS = {"weact.campact.de", "openpetition.de"}
# Tavily's include_domains is not guaranteed strict — validate in Python.
_PETITION_PATH_MARKERS = {"/petition/", "/p/"}
_TAVILY_QUERY = "Petition Politik Bundestag unterzeichnen 2026"
_CSE_QUERY = "site:openpetition.de OR site:weact.campact.de Petition unterzeichnen"


class CivilPetitionAdapter:
    """Fetches active civil-society petitions from WeAct/openpetition."""

    def __init__(
        self, tavily: TavilyClient, google_cse: GoogleCseAdapter | None = None
    ) -> None:
        self._tavily = tavily
        self._google_cse = google_cse

    async def fetch_new_items(self, since: datetime) -> list[RawSourceItem]:  # noqa: ARG002
        """`since` is unused — this source is re-searched in full each run,
        there is no incremental "updated since" concept for web search."""
        results = await self._tavily.search(
            _TAVILY_QUERY,
            max_results=15,
            days=14,
            include_domains=list(_PETITION_DOMAINS),
        )
        source = "tavily_petition_search"

        if not results and self._google_cse is not None:
            logger.info("Tavily returned no petitions — falling back to Google CSE")
            cse_items = await self._google_cse.search(_CSE_QUERY, max_results=10)
            results = [_normalize_cse_item(item) for item in cse_items]
            source = "google_cse_petition_search"

        return _parse_results(results, source)

    async def fetch_item_detail(self, external_id: str) -> RawSourceItem:
        raise NotImplementedError(
            "Civil petitions are re-fetched in full each run; there is no "
            "single-item detail endpoint."
        )


def _normalize_cse_item(item: dict[str, object]) -> dict[str, object]:
    """Maps a Google CSE result item to the same shape as a Tavily result."""
    return {
        "url": item.get("link", ""),
        "title": item.get("title", ""),
        "content": item.get("snippet", ""),
    }


def _parse_results(results: list[dict[str, object]], source: str) -> list[RawSourceItem]:
    items: list[RawSourceItem] = []
    for r in results:
        url = str(r.get("url") or "")
        if not url or not _is_valid_petition_url(url):
            logger.debug("Skipping non-petition URL %s", url)
            continue
        title = str(r.get("title") or "")
        content = str(r.get("content") or "")
        external_id = url.rstrip("/").split("/")[-1] or url[-40:]
        items.append(
            RawSourceItem(
                external_id=external_id,
                title=title,
                type="petition",
                status="offen",
                deadline=None,
                source_url=url,
                description=content[:500],
                initiated_by="Zivilgesellschaft",
                source=source,
            )
        )
    return items


def _is_valid_petition_url(url: str) -> bool:
    parsed = urlparse(url)
    host = parsed.netloc.lower().removeprefix("www.")
    if host not in _PETITION_DOMAINS:
        return False
    path = parsed.path
    # openpetition.de/at/ is the Austrian content section — exclude it
    if path.startswith("/at/"):
        return False
    # /petition/blog/ URLs are update pages, not the petition itself
    if "/petition/blog" in path:
        return False
    return any(marker in path for marker in _PETITION_PATH_MARKERS)
