"""Tavily search client — context enrichment and domain-restricted petition search."""

import logging

import httpx

logger = logging.getLogger(__name__)

_TAVILY_URL = "https://api.tavily.com/search"
_MAX_CONTEXT_CHARS = 2000


class TavilyClient:
    """Wraps the Tavily search API for two use cases:
    - enrich(): fetch background context for Mistral classification (Stage 4)
    - search(): domain-restricted search for civil society petitions (Stage 1)
    """

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def enrich(self, title: str) -> str:
        """Returns up to 2000 chars of web context for the given title.

        Returns empty string on any error so the pipeline can continue.
        """
        query = f"{title} Bundestag Hintergründe Auswirkungen"
        results = await self.search(query, max_results=3)
        return "\n\n".join(
            str(r.get("content", "")) for r in results if r.get("content")
        )[:_MAX_CONTEXT_CHARS]

    async def search(
        self,
        query: str,
        *,
        max_results: int = 3,
        days: int = 30,
        include_domains: list[str] | None = None,
    ) -> list[dict[str, object]]:
        """Returns raw Tavily result dicts. Returns [] on any error."""
        payload: dict[str, object] = {
            "api_key": self._api_key,
            "query": query,
            "search_depth": "basic",
            "max_results": max_results,
            "days": days,
        }
        if include_domains:
            payload["include_domains"] = include_domains
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.post(_TAVILY_URL, json=payload)
                response.raise_for_status()
            data: dict[str, object] = response.json()
            results = data.get("results") or []
            assert isinstance(results, list)
            return results
        except Exception as exc:
            logger.warning("Tavily search failed for %r: %s", query[:60], exc)
            return []
