#!/usr/bin/env python3
"""Coverage audit for the DIP adapter — are our beratungsstand/date filters
too strict, causing us to silently drop Vorgänge that are genuinely active?

This is a standalone diagnostic, not part of the pipeline: it queries DIP's
`/vorgang` endpoint with NO beratungsstand filter (only a wahlperiode +
recency window) to get the full set of "anything touched recently," then
compares that against what `DipAdapter.fetch_new_items()` /
`fetch_open_petitions()` actually return. Anything in the broad set but not
in the adapter's output is a Vorgang we are currently missing — either
because its beratungsstand value isn't one we filter for, or because it
falls outside our date windows.

Run from the backend directory:
  python scripts/audit_dip_coverage.py [--days 30]

Or inside Docker:
  docker compose exec api python scripts/audit_dip_coverage.py [--days 30]

Requires MEINIMPACT_DIP_API_KEY to be set (.env or environment).
"""

import argparse
import asyncio
import sys
from collections import Counter
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import quote, urlencode

import httpx

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from meinimpact.core.config import get_settings  # noqa: E402
from meinimpact.infrastructure.sources.dip_adapter import DipAdapter  # noqa: E402

_BASE_URL = "https://search.dip.bundestag.de/api/v1"
_PAGE_SIZE = 50
# Generous vs. the adapter's own _MAX_PAGES=20 — this query is intentionally
# unbounded by beratungsstand, so it needs more headroom before we call it
# "truncated" rather than actually crashing like the adapter does.
_AUDIT_MAX_PAGES = 80


async def _resolve_current_wahlperiode(client: httpx.AsyncClient, api_key: str) -> int | None:
    """Same approach as DipAdapter._resolve_current_wahlperiode: take the
    wahlperiode of the single most recently updated Vorgang."""
    since = (datetime.now(UTC) - timedelta(days=7)).date().isoformat()
    params = [
        ("apikey", api_key),
        ("format", "json"),
        ("rows", 1),
        ("f.datum.start", since),
    ]
    qs = urlencode(params, quote_via=quote)
    response = await client.get(f"{_BASE_URL}/vorgang?{qs}")
    response.raise_for_status()
    docs = response.json().get("documents") or []
    if not docs:
        return None
    wp = docs[0].get("wahlperiode")
    return wp if isinstance(wp, int) else None


async def _fetch_broad(
    client: httpx.AsyncClient, api_key: str, wahlperiode: int | None, since: str
) -> tuple[list[dict[str, object]], bool]:
    """Fetches every Vorgang updated since `since`, scoped to `wahlperiode`
    if resolved, with NO beratungsstand or vorgangstyp filter at all.

    Returns (docs, truncated) — truncated=True means we hit _AUDIT_MAX_PAGES
    before the cursor stopped changing, so the coverage numbers below are a
    lower bound, not exact.
    """
    all_docs: list[dict[str, object]] = []
    prev_cursor: str | None = None
    truncated = False

    for _ in range(_AUDIT_MAX_PAGES):
        params: list[tuple[str, str | int]] = [
            ("apikey", api_key),
            ("format", "json"),
            ("rows", _PAGE_SIZE),
            ("f.datum.start", since),
        ]
        if wahlperiode is not None:
            params.append(("f.wahlperiode", wahlperiode))
        if prev_cursor is not None:
            params.append(("cursor", prev_cursor))

        qs = urlencode(params, quote_via=quote)
        response = await client.get(f"{_BASE_URL}/vorgang?{qs}")
        response.raise_for_status()
        data = response.json()

        docs = data.get("documents") or []
        all_docs.extend(docs)

        new_cursor = data.get("cursor")
        if new_cursor == prev_cursor:
            return all_docs, truncated
        prev_cursor = new_cursor
    else:
        truncated = True

    return all_docs, truncated


async def run_audit(days: int) -> None:
    settings = get_settings()
    if not settings.dip_api_key:
        print("MEINIMPACT_DIP_API_KEY is not set — cannot query the live DIP API.")
        return

    api_key = settings.dip_api_key
    since = (datetime.now(UTC) - timedelta(days=days)).date().isoformat()

    async with httpx.AsyncClient(timeout=30.0) as client:
        wahlperiode = await _resolve_current_wahlperiode(client, api_key)
        broad_docs, truncated = await _fetch_broad(client, api_key, wahlperiode, since)

    adapter = DipAdapter(api_key)
    covered_items = await adapter.fetch_new_items(datetime.now(UTC) - timedelta(days=days))
    covered_petitions = await adapter.fetch_open_petitions()
    covered_ids = {item["external_id"] for item in covered_items}
    covered_ids |= {item["external_id"] for item in covered_petitions}

    broad_by_id = {str(d.get("id")): d for d in broad_docs}
    uncovered = {eid: d for eid, d in broad_by_id.items() if eid not in covered_ids}

    print(f"Window: last {days} day(s), since {since}")
    print(f"Wahlperiode resolved: {wahlperiode!r}")
    if truncated:
        print(
            f"WARNING: broad query hit the {_AUDIT_MAX_PAGES}-page cap before "
            "exhausting its cursor — numbers below are a LOWER BOUND, not exact. "
            "Re-run with a smaller --days window."
        )
    print()
    print(f"Total Vorgänge in broad (unfiltered) query: {len(broad_by_id)}")
    print(f"Covered by current adapter passes:          {len(covered_ids & set(broad_by_id))}")
    print(f"Uncovered (in DIP, missed by our filters):  {len(uncovered)}")
    if broad_by_id:
        pct = 100 * len(covered_ids & set(broad_by_id)) / len(broad_by_id)
        print(f"Coverage: {pct:.1f}%")
    print()

    beratungsstand_all = Counter(str(d.get("beratungsstand") or "(none)") for d in broad_docs)
    beratungsstand_uncovered = Counter(
        str(d.get("beratungsstand") or "(none)") for d in uncovered.values()
    )

    print("=== beratungsstand distribution (ALL Vorgänge in window) ===")
    for stand, count in beratungsstand_all.most_common():
        print(f"  {count:4d}  {stand}")

    print()
    print("=== beratungsstand distribution (UNCOVERED Vorgänge only) ===")
    if not beratungsstand_uncovered:
        print("  (none — every beratungsstand value in the window is fully covered)")
    for stand, count in beratungsstand_uncovered.most_common():
        print(f"  {count:4d}  {stand}")

    print()
    print("=== vorgangstyp distribution (UNCOVERED Vorgänge only) ===")
    vorgangstyp_uncovered = Counter(str(d.get("vorgangstyp") or "(none)") for d in uncovered.values())
    for typ, count in vorgangstyp_uncovered.most_common():
        print(f"  {count:4d}  {typ}")

    print()
    print("=== sample uncovered items (up to 15) ===")
    for eid, d in list(uncovered.items())[:15]:
        print(f"  [{eid}] ({d.get('beratungsstand')!r}, {d.get('vorgangstyp')!r}) {d.get('titel')}")

    # ------------------------------------------------------------------
    # Open question 1: what vorgangstyp do the beratungsstand="(none)"
    # items actually have? If any of them are Antrag/Gesetzentwurf, our
    # purely status-based filter can never match them — a silent hole.
    # ------------------------------------------------------------------
    none_status_docs = [d for d in broad_docs if not d.get("beratungsstand")]
    print()
    print(f"=== vorgangstyp breakdown for beratungsstand=(none) items ({len(none_status_docs)} total) ===")
    none_status_typ = Counter(str(d.get("vorgangstyp") or "(none)") for d in none_status_docs)
    for typ, count in none_status_typ.most_common():
        print(f"  {count:4d}  {typ}")
    print("  sample:")
    for d in none_status_docs[:8]:
        print(f"    [{d.get('id')}] ({d.get('vorgangstyp')!r}) {d.get('titel')}")

    # ------------------------------------------------------------------
    # Open question 2: full type x status cross-tab for vorgangstyp
    # containing "Petition", so we can see every beratungsstand wording
    # petitions actually carry — not just "Noch nicht beraten".
    # ------------------------------------------------------------------
    petition_docs = [
        d for d in broad_docs if "petition" in str(d.get("vorgangstyp") or "").lower()
    ]
    print()
    print(f"=== beratungsstand breakdown for vorgangstyp containing 'Petition' ({len(petition_docs)} total) ===")
    petition_status = Counter(str(d.get("beratungsstand") or "(none)") for d in petition_docs)
    for status, count in petition_status.most_common():
        covered_count = sum(
            1 for d in petition_docs if str(d.get("beratungsstand") or "(none)") == status
            and str(d.get("id")) in covered_ids
        )
        print(f"  {count:4d}  {status!r}  (covered: {covered_count})")

    # ------------------------------------------------------------------
    # Full type x status cross-tab, general purpose — lets us eyeball
    # every combination at once instead of two separate marginals.
    # ------------------------------------------------------------------
    print()
    print("=== full vorgangstyp x beratungsstand cross-tab (UNCOVERED only) ===")
    cross: Counter[tuple[str, str]] = Counter(
        (str(d.get("vorgangstyp") or "(none)"), str(d.get("beratungsstand") or "(none)"))
        for d in uncovered.values()
    )
    for (typ, status), count in cross.most_common(40):
        print(f"  {count:4d}  {typ!r:45s} {status!r}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--days", type=int, default=30, help="Lookback window in days (default: 30)"
    )
    args = parser.parse_args()
    asyncio.run(run_audit(args.days))
