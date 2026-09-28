#!/usr/bin/env python3
"""Step 1 dry-run: category-free retrieval test across three regions.

Rounds 1-5 (see project memory `project_tavily_retrieval_calibration.md`)
tested per-tag, per-axis-bin queries (the `(tag, axis_bin, region)` box
model) and found: `include_domains` isn't a hard guarantee (needs a code
post-filter), Tavily needs full natural-language intent descriptions (not
keyword strings) with enough concrete vocabulary to outweigh shared
boilerplate, axis framing works but exposed a real source-coverage gap for
market-leaning content, and several sources (epetitionen.bundestag.de,
dip.bundestag.de, and the advocacy-org sites) were dropped for reliability
or relevance reasons. Allowlist is now simplified to the two sources that
consistently worked: openpetition.de and weact.campact.de.

This round asks a different question: instead of searching *for* a
specific tag, ask Tavily a single, extensively-explained "what's
currently relevant and has real impact, no topic specified" query per
region, then manually categorize whatever comes back against the 14-tag
taxonomy. Goal: see whether natural topic diversity emerges well enough
to reduce or replace the per-(tag, axis_bin) box search strategy.

Sachsen and Dresden use a narrower allowlist (openpetition.de only) than
Bund — WeAct/Campact campaigns have looked nationally-coordinated in
every round so far, rarely hyper-local; this is an assumption, not a
finding, worth revisiting if Dresden turns up thin.

Pure read-only — no DB writes, no extraction. Prints results to the
console and dumps them to a JSON file for later reference/diffing.

Run from the backend directory:
  python scripts/dryrun_retrieval.py

Requires MEINIMPACT_TAVILY_API_KEY in .env or env. 3 queries this round
(one per region) — believed to be 1 credit each regardless of max_results.
"""

import asyncio
import json
import os
import sys
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlparse

# Allow running from backend root without installing the package
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

# Load .env manually (no python-dotenv needed)
_env_path = Path(__file__).parent.parent / ".env"
if _env_path.exists():
    for line in _env_path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())

from meinimpact.infrastructure.sources.tavily_client import TavilyClient  # noqa: E402

TAVILY_API_KEY = os.environ["MEINIMPACT_TAVILY_API_KEY"]

_MAX_RESULTS = 20
_DAYS = 365

# Only the two sources that consistently produced real, readable,
# actionable content across rounds 1-5. Everything else (advocacy-org
# sites, epetitionen.bundestag.de, dip.bundestag.de) was dropped for
# specific evidenced reasons — see project_tavily_retrieval_calibration.md.
_BUND_ALLOWLIST = ["openpetition.de", "weact.campact.de"]

# Sachsen: the Landtag's own e-petition system (state-level analogue of
# epetitionen.bundestag.de — untested, may or may not share its
# reliability problems) and Sachsen's own citizen participation portal.
_SACHSEN_ALLOWLIST = [
    "openpetition.de",
    "petition.landtag.sachsen.de",
    "buergerbeteiligung.sachsen.de",
]

# Dresden: the city's own participation section (path-restricted below —
# dresden.de is a huge general city site, most of it irrelevant) and its
# Ratsinformationssystem (council agenda/resolutions system).
_DRESDEN_ALLOWLIST = ["openpetition.de", "dresden.de", "ratsinfo.dresden.de"]

_PATH_ALLOWLIST: dict[str, list[str]] = {
    "openpetition.de": ["/petition/online/"],
    "weact.campact.de": ["/petitions/", "/efforts/"],
    "dresden.de": ["/de/leben/gesellschaft/buergerbeteiligung"],
}
# buergerbeteiligung.sachsen.de mixes real consultations with legal
# boilerplate under the same URL shape (/portal/{agency}/beteiligung/
# themen/{id}) — only the clear junk (accessibility statements, imprint,
# etc., all under /informationen/) can be filtered by path. Distinguishing
# a real consultation from a webinar announcement or a slogan contest
# needs extraction to judge, not a path rule.
_PATH_BLOCKLIST: dict[str, list[str]] = {
    "buergerbeteiligung.sachsen.de": ["/informationen/"],
}

# ---------------------------------------------------------------------------
# Category-free queries — no tag, no keyword list, no axis framing. Each
# is an extensive natural-language description of what "relevant and
# impactful right now" means, so Tavily's own semantic ranking decides
# what qualifies rather than us pre-selecting a topic.
# ---------------------------------------------------------------------------

REGIONS: dict[str, dict[str, object]] = {
    "bund": {
        "allowlist": _BUND_ALLOWLIST,
        "query": (
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
    },
    "sachsen": {
        "allowlist": _SACHSEN_ALLOWLIST,
        "query": (
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
    },
    "dresden": {
        "allowlist": _DRESDEN_ALLOWLIST,
        "query": (
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
    },
}


def _domain(url: str) -> str:
    return urlparse(url).netloc.removeprefix("www.")


def _normalize(url: str) -> str:
    parsed = urlparse(url)
    return f"{parsed.netloc.removeprefix('www.')}{parsed.path}"


def _is_allowed_domain(domain: str, allowlist: list[str]) -> bool:
    """Hard post-filter — round 4 proved `include_domains` silently
    backfills from the open web when the allowlist doesn't have enough
    matches, so we can never trust it alone. Matches subdomains too."""
    return any(domain == d or domain.endswith(f".{d}") for d in allowlist)


def _passes_path_filter(domain: str, url: str) -> bool:
    path = urlparse(url).path
    prefixes = _PATH_ALLOWLIST.get(domain)
    if prefixes is not None and not any(path.startswith(p) for p in prefixes):
        return False
    blocked = _PATH_BLOCKLIST.get(domain, [])
    return not any(b in path for b in blocked)


async def run_query(
    client: TavilyClient, label: str, query: str, allowlist: list[str]
) -> dict[str, object]:
    print(f"\n{'=' * 70}")
    print(f"[{label}]  (allowlist: {allowlist})")
    print(f"query: {query}")
    print(f"{'=' * 70}")

    raw_results = await client.search(
        query,
        max_results=_MAX_RESULTS,
        days=_DAYS,
        include_domains=allowlist,
    )

    seen_normalized: set[str] = set()
    results = []
    off_allowlist = 0
    path_filtered = 0
    collapsed = 0
    for r in raw_results:
        url = str(r.get("url", ""))
        domain = _domain(url)
        if not _is_allowed_domain(domain, allowlist):
            off_allowlist += 1
            continue
        if not _passes_path_filter(domain, url):
            path_filtered += 1
            continue
        norm = _normalize(url)
        if norm in seen_normalized:
            collapsed += 1
            continue
        seen_normalized.add(norm)
        results.append(r)
    if off_allowlist:
        print(f"  (dropped {off_allowlist} results outside the allowlist)")
    if path_filtered:
        print(f"  (dropped {path_filtered} results failing the per-domain path filter)")
    if collapsed:
        print(f"  (collapsed {collapsed} same-page language/query-param variants)")

    out_results = []
    for r in results:
        url = str(r.get("url", ""))
        domain = _domain(url)
        print(f"\n  - {r.get('title', '(no title)')}")
        print(f"    domain: {domain}")
        print(f"    url:    {url}")
        content = str(r.get("content", ""))
        print(f"    snippet: {content[:280]}")
        out_results.append(
            {
                "title": r.get("title"),
                "url": url,
                "domain": domain,
                "content": content,
                "score": r.get("score"),
                "published_date": r.get("published_date"),
            }
        )

    print(f"\n  → {len(results)} results")

    return {
        "label": label,
        "query": query,
        "allowlist": allowlist,
        "result_count": len(results),
        "results": out_results,
    }


async def main() -> None:
    client = TavilyClient(TAVILY_API_KEY)
    run_output: dict[str, object] = {
        "run_at": datetime.now(UTC).isoformat(),
        "max_results": _MAX_RESULTS,
        "days": _DAYS,
        "queries": [],
    }

    for label, cfg in REGIONS.items():
        result = await run_query(
            client, label, cfg["query"], cfg["allowlist"]  # type: ignore[arg-type]
        )
        run_output["queries"].append(result)  # type: ignore[attr-defined]

    out_dir = Path(__file__).parent / "dryrun_output"
    out_dir.mkdir(exist_ok=True)
    out_path = out_dir / f"retrieval_{datetime.now(UTC):%Y%m%d_%H%M%S}.json"
    out_path.write_text(json.dumps(run_output, indent=2, ensure_ascii=False))

    print(f"\n{'=' * 70}")
    print(f"Saved full output to {out_path}")
    print(f"{'=' * 70}")


if __name__ == "__main__":
    asyncio.run(main())
