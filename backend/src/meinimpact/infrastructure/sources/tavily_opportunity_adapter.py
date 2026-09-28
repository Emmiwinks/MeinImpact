"""Tavily-based opportunity discovery — category-free, per-region queries.

Promoted from `scripts/dryrun_retrieval.py` once six rounds of hand-testing
(see project memory `project_tavily_retrieval_calibration.md`) settled the
approach: no per-tag/per-axis-bin "box" search — a single, extensively
explained "what's currently relevant and has real impact, no topic
specified" query per region, letting Tavily's own semantic ranking (and
later, extraction) decide what qualifies rather than us pre-selecting a
topic. Region queries are phrased for genuine local relevance, not a bund
query with a place name appended, per the plan's own warning.

`include_domains` is not a hard guarantee (round 4 found Tavily silently
backfills from the open web when the allowlist doesn't have enough
matches) — this adapter always applies a hard code-level domain filter
regardless of what's passed to the API.
"""

from dataclasses import dataclass
from typing import TypedDict
from urllib.parse import urlparse

from meinimpact.infrastructure.sources.tavily_client import TavilyClient

_MAX_RESULTS = 20
_DAYS = 365


class RawOpportunityItem(TypedDict):
    """One retrieval result surviving domain/path/dedup filtering, ready
    for extraction."""

    title: str
    url: str
    domain: str
    source_org: str
    content: str
    region: str


@dataclass(frozen=True)
class RegionConfig:
    allowlist: list[str]
    query: str


# Display names for source_org — see rebuild plan section 1 ("always
# populated, always shown in the UI"). Falls back to the bare domain for
# anything not listed (shouldn't happen for allowlisted domains below).
_SOURCE_ORG_NAMES: dict[str, str] = {
    "openpetition.de": "openPetition",
    "weact.campact.de": "WeAct/Campact",
    "buergerbeteiligung.sachsen.de": "Beteiligungsportal Sachsen",
    "petition.landtag.sachsen.de": "Sächsischer Landtag",
    "dresden.de": "Landeshauptstadt Dresden",
    "ratsinfo.dresden.de": "Ratsinformationssystem Dresden",
}

# Only the sources that survived calibration — see
# project_tavily_retrieval_calibration.md for what was dropped and why
# (mieterbund.de, mehr-demokratie.de, vzbv.de, campact.de: advocacy-org
# content, not actionable campaigns; epetitionen.bundestag.de: unreliable
# rendering + weak relevance; dip.bundestag.de: unreadable by Tavily).
_BUND_ALLOWLIST = ["openpetition.de", "weact.campact.de"]
_SACHSEN_ALLOWLIST = [
    "openpetition.de",
    "petition.landtag.sachsen.de",
    "buergerbeteiligung.sachsen.de",
]
_DRESDEN_ALLOWLIST = ["openpetition.de", "dresden.de", "ratsinfo.dresden.de"]

# Tavily only restricts by domain, not path — these domains proved to
# serve non-actionable meta/listing/blog/forum pages alongside real
# petitions/consultations.
_PATH_ALLOWLIST: dict[str, list[str]] = {
    "openpetition.de": ["/petition/online/"],
    "weact.campact.de": ["/petitions/", "/efforts/"],
    "dresden.de": ["/de/leben/gesellschaft/buergerbeteiligung"],
}
# buergerbeteiligung.sachsen.de mixes real consultations with legal
# boilerplate under the same URL shape — only the clear junk
# (accessibility statements etc., all under /informationen/) can be
# filtered by path. Distinguishing a real consultation from a webinar
# announcement or a slogan contest needs extraction to judge, not a
# path rule.
_PATH_BLOCKLIST: dict[str, list[str]] = {
    "buergerbeteiligung.sachsen.de": ["/informationen/"],
}

REGIONS: dict[str, RegionConfig] = {
    "bund": RegionConfig(
        allowlist=_BUND_ALLOWLIST,
        query=(
            "Welche aktuellen Petitionen, Bürgerinitiativen und Kampagnen "
            "in Deutschland sind gerade besonders wichtig und relevant für "
            "das Alltagsleben der Menschen? Gesucht sind laufende, "
            "konkrete Möglichkeiten zur Beteiligung — unabhängig vom "
            "Themenbereich —, die eine echte, spürbare Auswirkung auf das "
            "Leben von Bürgerinnen und Bürgern haben, zum Beispiel auf "
            "ihre finanzielle Situation, ihre Gesundheit, ihre "
            "Wohnsituation, ihre Arbeit, ihre Sicherheit oder ihr "
            "unmittelbares Lebensumfeld. Nicht gesucht sind reine "
            "Nachrichtenartikel, Berichte oder allgemeine "
            "Diskussionsbeiträge ohne konkrete Beteiligungsmöglichkeit."
        ),
    ),
    "sachsen": RegionConfig(
        allowlist=_SACHSEN_ALLOWLIST,
        query=(
            "Welche aktuellen Petitionen, Bürgerinitiativen und Kampagnen "
            "mit Bezug zu Sachsen sind gerade besonders wichtig für das "
            "Alltagsleben der Menschen dort? Gesucht sind laufende, "
            "konkrete Beteiligungsmöglichkeiten zu Themen, die speziell "
            "für Sachsen oder einzelne sächsische Städte und Regionen "
            "relevant sind — unabhängig vom Themenbereich —, mit echter "
            "Auswirkung auf das Leben der Menschen vor Ort. Nicht gesucht "
            "sind reine Nachrichtenartikel oder bundesweite Kampagnen ohne "
            "besonderen Sachsen-Bezug."
        ),
    ),
    "dresden": RegionConfig(
        allowlist=_DRESDEN_ALLOWLIST,
        query=(
            "Welche aktuellen Petitionen, Bürgerinitiativen und Kampagnen "
            "mit Bezug zu Dresden sind gerade besonders wichtig für das "
            "Alltagsleben der Menschen dort? Gesucht sind laufende, "
            "konkrete Beteiligungsmöglichkeiten zu Themen, die speziell "
            "für die Stadt Dresden relevant sind — unabhängig vom "
            "Themenbereich —, mit echter Auswirkung auf den Alltag der "
            "Menschen vor Ort, zum Beispiel zu städtischen Bauprojekten, "
            "Verkehr, Wohnen oder dem lokalen Lebensumfeld. Nicht gesucht "
            "sind reine Nachrichtenartikel oder bundesweite Kampagnen ohne "
            "besonderen Dresden-Bezug."
        ),
    ),
}


def _domain(url: str) -> str:
    return urlparse(url).netloc.removeprefix("www.")


def _normalize(url: str) -> str:
    """Strips query string and fragment so language-variant pages of the
    same underlying resource count as one page, not several."""
    parsed = urlparse(url)
    return f"{parsed.netloc.removeprefix('www.')}{parsed.path}"


def _is_allowed_domain(domain: str, allowlist: list[str]) -> bool:
    """Hard post-filter — Tavily's `include_domains` silently backfills
    from the open web when the allowlist doesn't have enough matches, so
    it can never be trusted alone. Matches subdomains too."""
    return any(domain == d or domain.endswith(f".{d}") for d in allowlist)


def _passes_path_filter(domain: str, url: str) -> bool:
    path = urlparse(url).path
    prefixes = _PATH_ALLOWLIST.get(domain)
    if prefixes is not None and not any(path.startswith(p) for p in prefixes):
        return False
    blocked = _PATH_BLOCKLIST.get(domain, [])
    return not any(b in path for b in blocked)


def _source_org_for(domain: str) -> str:
    return _SOURCE_ORG_NAMES.get(domain, domain)


class TavilyOpportunityAdapter:
    """Fetches and filters raw opportunity candidates for one region."""

    def __init__(self, client: TavilyClient) -> None:
        self._client = client

    async def fetch(self, region: str) -> list[RawOpportunityItem]:
        """Returns filtered, deduplicated raw results for `region`."""
        cfg = REGIONS[region]
        raw_results = await self._client.search(
            cfg.query,
            max_results=_MAX_RESULTS,
            days=_DAYS,
            include_domains=cfg.allowlist,
        )

        seen_normalized: set[str] = set()
        items: list[RawOpportunityItem] = []
        for r in raw_results:
            url = str(r.get("url", ""))
            domain = _domain(url)
            if not _is_allowed_domain(domain, cfg.allowlist):
                continue
            if not _passes_path_filter(domain, url):
                continue
            norm = _normalize(url)
            if norm in seen_normalized:
                continue
            seen_normalized.add(norm)
            items.append(
                RawOpportunityItem(
                    title=str(r.get("title", "")),
                    url=url,
                    domain=domain,
                    source_org=_source_org_for(domain),
                    content=str(r.get("content", "")),
                    region=region,
                )
            )
        return items
