#!/usr/bin/env python3
"""Syncs the PLZ table (PLZ -> Kreis and point) from GeoNames into its
committed data file.

Covers all of Germany, so a new city needs no run of its own. Run
occasionally to pick up new PLZs, then review the diff and commit:
  docker compose exec api python scripts/sync_plz.py
"""

import asyncio
import json
from datetime import UTC, datetime

from meinimpact.infrastructure.geo.geonames import (
    ATTRIBUTION,
    GeoNamesPlzSource,
    condense,
)
from meinimpact.infrastructure.geo.plz import DATA_FILE


async def main() -> None:
    source = GeoNamesPlzSource()
    try:
        rows = await source.fetch()
    finally:
        await source.aclose()

    condensed = condense(rows)
    # One PLZ per line: small, reviewable diffs.
    entries = ",\n".join(
        f"    {json.dumps(plz)}: {json.dumps(list(entry))}"
        for plz, entry in condensed.items()
    )
    DATA_FILE.parent.mkdir(exist_ok=True)
    DATA_FILE.write_text(
        "{\n"
        f'  "source": {json.dumps(ATTRIBUTION)},\n'
        f'  "synced_at": "{datetime.now(UTC).date().isoformat()}",\n'
        '  "fields": ["kreis", "lat", "lon"],\n'
        f'  "plz": {{\n{entries}\n  }}\n'
        "}\n",
        "utf-8",
    )
    print(f"{len(condensed)} PLZ from {len(rows)} places -> {DATA_FILE}")


if __name__ == "__main__":
    asyncio.run(main())
