"""Dry run of the council member sync against live OParl (no database).

Prints how many current voting members each body in scope has, every
Fraktion with its member count and whether an office address is known, and
the people without a Fraktion. Takes about ten minutes (one polite walk over
the people list).

    docker compose exec api python scripts/dryrun_council_members.py
"""

import asyncio
from collections import Counter
from datetime import UTC, datetime

from meinimpact.infrastructure.council.offices import FRAKTION_OFFICES
from meinimpact.infrastructure.council.oparl_members import fetch_council_members
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.sources.oparl import DRESDEN


async def main() -> None:
    async with PoliteHttpClient() as http:
        members = await fetch_council_members(
            http, DRESDEN, today=datetime.now(UTC).date()
        )

    print(f"{len(members)} seats, {len({m.person_url for m in members})} people\n")
    print("Seats per body:")
    for name, count in sorted(Counter(m.organization_name for m in members).items()):
        print(f"  {count:3}  {name}")

    print("\nFraktionen (people, office address):")
    people = {m.person_url: m for m in members}.values()
    fraktionen = Counter((m.fraktion_url, m.fraktion_name) for m in people)
    for (url, name), count in sorted(fraktionen.items(), key=lambda x: str(x[0][1])):
        address = FRAKTION_OFFICES.get(url, "-- none --") if url else ""
        print(f"  {count:3}  {name or '(no Fraktion)'}  {url or ''}  {address}")

    print("\nSeats of people in a Fraktion without an office address:")
    for m in members:
        if m.fraktion_url and m.fraktion_url not in FRAKTION_OFFICES:
            print(f"  {m.person_name} ({m.fraktion_name}): {m.organization_name}")

    council = [m for m in members if m.organization_name == DRESDEN.council]
    print(f"\n{DRESDEN.council}: {len(council)} voting members, without Fraktion:")
    for m in council:
        if not m.fraktion_url:
            print(f"  {m.person_name}")


if __name__ == "__main__":
    asyncio.run(main())
