#!/usr/bin/env python3
"""Syncs the PLZ table (PLZ -> Kreis and point) and the place table
(municipality and Kreis names -> where they lie) from GeoNames into their
committed data files.

Covers all of Germany, so a new city needs no run of its own. Run
occasionally to pick up new PLZs, then review the diff and commit:
  docker compose exec api python scripts/sync_plz.py
"""

import asyncio
import json
from datetime import UTC, datetime

from meinimpact.infrastructure.geo import places, plz
from meinimpact.infrastructure.geo.geonames import (
    ATTRIBUTION,
    GeoNamesPlzSource,
    condense,
    condense_places,
    kreis_names,
)


def _lines(entries: dict[str, object]) -> str:
    """One entry per line: small, reviewable diffs."""
    return ",\n".join(
        f"    {json.dumps(key, ensure_ascii=False)}: "
        f"{json.dumps(value, ensure_ascii=False)}"
        for key, value in entries.items()
    )


async def main() -> None:
    source = GeoNamesPlzSource()
    try:
        rows = await source.fetch()
    finally:
        await source.aclose()

    synced_at = datetime.now(UTC).date().isoformat()
    condensed = condense(rows)
    plz.DATA_FILE.parent.mkdir(exist_ok=True)
    plz.DATA_FILE.write_text(
        "{\n"
        f'  "source": {json.dumps(ATTRIBUTION)},\n'
        f'  "synced_at": "{synced_at}",\n'
        '  "fields": ["kreis", "lat", "lon"],\n'
        f'  "plz": {{\n{_lines({k: list(v) for k, v in condensed.items()})}\n  }}\n'
        "}\n",
        "utf-8",
    )
    print(f"{len(condensed)} PLZ from {len(rows)} places -> {plz.DATA_FILE}")

    municipalities = condense_places(rows)
    kreise = kreis_names(rows)
    places.DATA_FILE.write_text(
        "{\n"
        f'  "source": {json.dumps(ATTRIBUTION)},\n'
        f'  "synced_at": "{synced_at}",\n'
        f'  "kreise": {{\n{_lines(kreise)}\n  }},\n'
        '  "fields": ["kreis", "lat", "lon", "km"],\n'
        f'  "places": {{\n{_lines({k: [list(e) for e in v] for k, v in municipalities.items()})}\n  }}\n'
        "}\n",
        "utf-8",
    )
    print(
        f"{len(municipalities)} place names, {len(kreise)} Kreis names"
        f" -> {places.DATA_FILE}"
    )


if __name__ == "__main__":
    asyncio.run(main())
