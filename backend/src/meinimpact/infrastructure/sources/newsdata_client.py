"""NewsData.io client for Stage 0 Topic Radar (Signal B: news attention).

Free tier: 200 credits/day. One search query = 1 credit.
We run at most one query per topic (10 topics max) = ≤10 credits/run.
"""

import logging

import httpx

logger = logging.getLogger(__name__)

_BASE_URL = "https://newsdata.io/api/1/latest"

# Maps our topic taxonomy to German search keywords for NewsData queries.
TOPIC_KEYWORDS: dict[str, list[str]] = {
    "klimaschutz":   ["Klimaschutz", "CO2", "Erneuerbare", "Energiewende"],
    "soziales":      ["Sozialleistungen", "Bürgergeld", "Rente", "Pflege"],
    "demokratie":    ["Demokratie", "Verfassung", "Wahl", "Rechtsstaat"],
    "bildung":       ["Bildung", "Schule", "BAföG", "Studium"],
    "gesundheit":    ["Gesundheit", "Krankenhaus", "Pflege", "Medizin"],
    "wirtschaft":    ["Wirtschaft", "Inflation", "Haushalt", "Unternehmen"],
    "wohnen":        ["Wohnen", "Miete", "Wohnungsbau", "Mietpreise"],
    "digital":       ["Digital", "Datenschutz", "KI", "Technologie"],
    "verkehr":       ["Verkehr", "Bahn", "Straßen", "Mobilität"],
    "aussenpolitik": ["Außenpolitik", "Ukraine", "NATO", "Diplomatie"],
}


class NewsDataClient:
    """Fetches German political news article counts per topic from NewsData.io."""

    def __init__(self, api_key: str) -> None:
        self._api_key = api_key

    async def count_articles_per_topic(self) -> dict[str, int]:
        """Returns article counts for each topic from the last 7 days.

        Runs one query per topic against the NewsData /latest endpoint.
        Returns 0 for any topic that errors (graceful degradation).
        """
        counts: dict[str, int] = {}
        async with httpx.AsyncClient(timeout=15.0) as client:
            for topic, keywords in TOPIC_KEYWORDS.items():
                counts[topic] = await self._count_for_topic(client, topic, keywords)
        return counts

    async def _count_for_topic(
        self, client: httpx.AsyncClient, topic: str, keywords: list[str]
    ) -> int:
        query = " OR ".join(keywords)
        try:
            response = await client.get(
                _BASE_URL,
                params={
                    "apikey": self._api_key,
                    "q": query,
                    "country": "de",
                    "category": "politics",
                    "language": "de",
                },
            )
            response.raise_for_status()
            data: dict[str, object] = response.json()
            results = data.get("results") or []
            assert isinstance(results, list)
            count = len(results)
            logger.debug("NewsData topic=%s articles=%d", topic, count)
            return count
        except Exception as exc:
            logger.warning("NewsData query failed for topic %r: %s", topic, exc)
            return 0
