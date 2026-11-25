#!/usr/bin/env python3
"""Syncs a council's Fraktion office addresses into its committed data file.

Reads the current Fraktionen from the place's OParl body. Reviewed entries
stay as they are; a Fraktion with an email in OParl and no entry yet gets
one (OParl as source). Prints the Fraktionen still without an address: find
each on the Fraktion's own or the city's page, add it to the file with that
page as `source`, review the diff and commit.

  docker compose exec api python scripts/sync_council_offices.py dresden
"""

import asyncio
import sys
from datetime import UTC, datetime

from meinimpact import places
from meinimpact.infrastructure.council.offices import (
    OfficeAddress,
    load_offices,
    save_offices,
)
from meinimpact.infrastructure.council.oparl_members import fetch_fraktionen
from meinimpact.infrastructure.listings.http import PoliteHttpClient


async def main(place_key: str) -> None:
    place = places.by_key(place_key)
    if place is None or place.oparl is None:
        raise SystemExit(f"no place {place_key!r} with an OParl body")
    today = datetime.now(UTC).date()
    async with PoliteHttpClient() as http:
        fraktionen = await fetch_fraktionen(http, place.oparl, today=today)

    offices = {o.organization: o for o in load_offices(place_key)}
    added = []
    for fraktion in fraktionen:
        if fraktion.url not in offices and fraktion.email:
            offices[fraktion.url] = OfficeAddress(
                organization=fraktion.url,
                fraktion=fraktion.name,
                email=fraktion.email,
                source=fraktion.url,
                verified_on=today.isoformat(),
            )
            added.append(fraktion.name)
    path = save_offices(place_key, offices.values())

    current = {f.url for f in fraktionen}
    missing = [f for f in fraktionen if f.url not in offices]
    ended = [o for o in offices.values() if o.organization not in current]
    print(f"{len(fraktionen)} current Fraktionen in {place.name} -> {path}")
    print(f"added from OParl: {', '.join(added) or 'none'}")
    if missing:
        print(
            "No address yet (OParl keeps dissolved Fraktionen open: check each "
            "is still active, or wait for the member sync's report on /admin):"
        )
    for fraktion in missing:
        print(f"  {fraktion.name}  {fraktion.url}")
    for office in ended:
        print(f"  ended in OParl, entry kept: {office.fraktion}  {office.organization}")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "dresden"))
