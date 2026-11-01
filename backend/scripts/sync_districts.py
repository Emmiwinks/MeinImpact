#!/usr/bin/env python3
"""Syncs a city's district list from Wikidata into its committed data file.

Run when adding a city (add its `CityConfig` to `geo/districts.py` first)
or occasionally to pick up corrections, then review the diff and commit:
  docker compose exec api python scripts/sync_districts.py dresden
"""

import asyncio
import json
import sys
from datetime import UTC, datetime

from meinimpact.infrastructure.geo.districts import CITIES, data_file
from meinimpact.infrastructure.geo.wikidata import WikidataDistrictSource


async def main(city_key: str) -> None:
    city = CITIES[city_key]
    source = WikidataDistrictSource()
    try:
        districts = await source.fetch(city)
    finally:
        await source.aclose()

    path = data_file(city)
    path.parent.mkdir(exist_ok=True)
    payload = {
        "city": city.name,
        "wikidata_id": city.wikidata_id,
        "district_types": list(city.district_types),
        "synced_at": datetime.now(UTC).date().isoformat(),
        "districts": [
            {"name": d.name, "wikidata_id": d.wikidata_id} for d in districts
        ],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", "utf-8")
    print(f"{len(districts)} districts for {city.name} -> {path}")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "dresden"))
