"""Google Custom Search API — fallback petition search.

Per specs/data/sources-federal.md "Source 4: Civil Society Petitions".
Used only when Tavily returns no results. Free tier: 100 queries/day
(not enforced client-side — quota errors are treated as "no results").
"""

import logging

import httpx

logger = logging.getLogger(__name__)

_BASE_URL = "https://www.googleapis.com/customsearch/v1"
_MAX_RESULTS_PER_REQUEST = 10  # Google CSE API hard limit


class GoogleCseAdapter:
    """Wraps the Google Custom Search JSON API."""

    def __init__(self, api_key: str, cse_id: str) -> None:
        self._api_key = api_key
        self._cse_id = cse_id

    async def search(self, query: str, *, max_results: int = 10) -> list[dict[str, object]]:
        """Returns raw Google CSE result items. Returns [] on any error,
        including quota exhaustion (403/429)."""
        params: dict[str, str | int] = {
            "key": self._api_key,
            "cx": self._cse_id,
            "q": query,
            "num": min(max_results, _MAX_RESULTS_PER_REQUEST),
        }
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(_BASE_URL, params=params)
                response.raise_for_status()
            data: dict[str, object] = response.json()
        except Exception as exc:
            logger.warning("Google CSE search failed for %r: %s", query[:60], exc)
            return []

        items = data.get("items") or []
        return items if isinstance(items, list) else []
