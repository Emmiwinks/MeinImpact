"""NewsData.io client — currently not used in the ingestion pipeline.

Previously used for topic-frequency scoring in Stage 0. The topic taxonomy
has been removed; hotness is now determined by DIP beratungsstand stage
and recency. This client is retained for potential future use (e.g. news
context enrichment or momentum boosting).

See specs/data/sources-federal.md — Source 5.
"""

import logging

import httpx

logger = logging.getLogger(__name__)

_BASE_URL = "https://newsdata.io/api/1/latest"


class NewsDataClient:
    """Fetches German political news articles from NewsData.io."""

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def fetch_recent_politics(self, max_results: int = 10) -> list[dict[str, object]]:
        """Returns recent German politics articles.

        Not called by the pipeline in MVP. Reserved for future news-context
        enrichment or momentum scoring use cases.
        """
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(
                    _BASE_URL,
                    params={
                        "apikey": self._api_key,
                        "country": "de",
                        "category": "politics",
                        "language": "de",
                    },
                )
                response.raise_for_status()
                data: dict[str, object] = response.json()
                results = data.get("results") or []
                assert isinstance(results, list)
                return results[:max_results]
        except Exception as exc:
            logger.warning("NewsData fetch failed: %s", exc)
            return []
