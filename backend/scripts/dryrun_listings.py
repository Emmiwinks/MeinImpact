#!/usr/bin/env python3
"""Dry run: read all configured registries and dump what they list.

Pure read-only: no DB, no LLM. Runs `catalog.default_sources`, applies
`steps.default_steps`, prints a per-source summary and writes
everything (including what the steps dropped) to
`scripts/dryrun_output/listings_<timestamp>.json`.

Run inside the API container:
  docker compose exec api python scripts/dryrun_listings.py
"""

import asyncio
import json
import sys
from collections import Counter
from collections.abc import Sequence
from dataclasses import asdict
from datetime import date, datetime
from enum import Enum
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from meinimpact.infrastructure.listings import steps
from meinimpact.infrastructure.listings.catalog import default_sources
from meinimpact.infrastructure.listings.collector import (
    SourceOutcome,
    collect,
)
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import Listing

_OUTPUT_DIR = Path(__file__).parent / "dryrun_output"


def _json_default(value: object) -> object:
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, datetime | date):
        return value.isoformat()
    raise TypeError(f"not JSON serializable: {type(value).__name__}")


def _print_summary(
    outcomes: Sequence[SourceOutcome], kept: list[Listing], everything: list[Listing]
) -> None:
    print(f"\n{'source':32} {'listed':>7} {'secs':>6}  status")
    for outcome in outcomes:
        status = "ok" if outcome.ok else f"FAILED {outcome.error}"
        print(
            f"{outcome.source:32} {len(outcome.listings):7} {outcome.duration_s:6.1f}  {status}"
        )

    print(f"\nlisted total: {len(everything)}  after steps: {len(kept)}")
    print("kept by region:", dict(Counter(str(item.region) for item in kept)))
    print("kept by kind:  ", dict(Counter(str(item.kind) for item in kept)))
    outside = Counter(item.locality for item in everything if item.region is None)
    print(
        f"outside coverage: {sum(outside.values())} from {len(outside)} authorities/localities"
    )
    for locality, count in outside.most_common(15):
        print(f"  {count:4}  {locality}")


async def main() -> None:
    async with PoliteHttpClient() as http:
        report = await collect(default_sources(http))

    everything = report.listings
    kept = steps.apply(everything, steps.default_steps(report.observed_at.date()))
    kept_ids = {id(item) for item in kept}
    _print_summary(report.outcomes, kept, everything)

    _OUTPUT_DIR.mkdir(exist_ok=True)
    path = _OUTPUT_DIR / f"listings_{report.observed_at:%Y%m%d_%H%M%S}.json"
    payload = {
        "observed_at": report.observed_at,
        "outcomes": [
            {
                "source": o.source,
                "count": len(o.listings),
                "duration_s": o.duration_s,
                "error": o.error,
            }
            for o in report.outcomes
        ],
        "kept": [asdict(item) for item in kept],
        "dropped": [asdict(item) for item in everything if id(item) not in kept_ids],
    }
    path.write_text(
        json.dumps(payload, default=_json_default, ensure_ascii=False, indent=2)
    )
    print(f"\nwrote {path}")


if __name__ == "__main__":
    asyncio.run(main())
