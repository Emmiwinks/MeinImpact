"""Tavily quality-media coverage check — state C determination.

Per specs/data/ingestion-pipeline.md "State C via Tavily": uses the DIP
Vorgang title or petition title verbatim as the search query — no keyword
dictionary, no RSS parsing. `QUALITY_MEDIA_DOMAINS` is the only constant to
maintain here.
"""

from urllib.parse import urlparse

from meinimpact.infrastructure.sources.protocol import MediaCoverageResult
from meinimpact.infrastructure.sources.tavily_client import TavilyClient

QUALITY_MEDIA_DOMAINS: list[str] = [
    "tagesschau.de",
    "zeit.de",
    "spiegel.de",
    "faz.net",
    "sueddeutsche.de",
    "mdr.de",
]

_LOOKBACK_DAYS = 14
_MAX_RESULTS = 5
_MIN_ARTICLES = 2
_MIN_DOMAINS = 2


class TavilyMediaCoverageAdapter:
    """Wraps `TavilyClient.search()` with the quality-media domain filter
    shared by both pipelines' state-C rule."""

    def __init__(self, client: TavilyClient) -> None:
        self._client = client

    async def check_coverage(self, query_text: str) -> MediaCoverageResult:
        """`query_text` is the DIP Vorgang title or petition title, used
        verbatim — no keyword mapping."""
        results = await self._client.search(
            query_text,
            include_domains=QUALITY_MEDIA_DOMAINS,
            days=_LOOKBACK_DAYS,
            max_results=_MAX_RESULTS,
        )
        domains = {
            _extract_domain(str(r.get("url", ""))) for r in results if r.get("url")
        }
        matched = len(results) >= _MIN_ARTICLES and len(domains) >= _MIN_DOMAINS
        return MediaCoverageResult(
            matched=matched,
            article_count=len(results),
            distinct_domains=len(domains),
        )


def _extract_domain(url: str) -> str:
    return urlparse(url).netloc.removeprefix("www.")
