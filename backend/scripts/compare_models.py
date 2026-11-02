#!/usr/bin/env python3
"""Compare enrichment quality of two Mistral models on the same stored cards.

Takes a deterministic sample of the active, relevant opportunities from the
DB (registry title/summary only, no detail pages, so both models see the same
input), runs the current enrichment prompt through each model and prints the
tags and Lebenslagen side by side. Nothing is written to the DB.

  docker compose exec api python scripts/compare_models.py \
      mistral-medium-latest mistral-large-latest 30
"""

import asyncio
import sys
from datetime import UTC, datetime

from sqlalchemy import select

from meinimpact.core.config import get_settings
from meinimpact.infrastructure.ai.listing_enricher import Enrichment, ListingEnricher
from meinimpact.infrastructure.ai.mistral_json import MistralJsonCompleter
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.listings.model import (
    ActionKind,
    Listing,
    ListingStatus,
    Region,
)
from meinimpact.infrastructure.models import OpportunityRecord

_CONCURRENCY = 4


def _listing(record: OpportunityRecord) -> Listing:
    return Listing(
        source_id=record.source_id,
        external_id=record.external_id,
        url=record.source_url,
        title=record.registry_title,
        kind=ActionKind(record.kind),
        status=ListingStatus(record.status),
        region=Region(record.registry_region) if record.registry_region else None,
        observed_at=datetime.now(UTC),
        locality=record.locality,
        organizer=record.organizer,
        summary=record.registry_summary,
        opens_on=record.opens_on,
        closes_on=record.closes_on,
        source_labels=tuple(record.source_labels or ()),
    )


async def _run(model: str, listings: list[Listing]) -> list[Enrichment | None]:
    settings = get_settings()
    completer = MistralJsonCompleter(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=model,
    )
    enricher = ListingEnricher(completer)
    gate = asyncio.Semaphore(_CONCURRENCY)

    async def one(listing: Listing) -> Enrichment | None:
        async with gate:
            try:
                return await enricher.enrich(listing, None)
            except Exception as error:  # report, keep comparing the rest
                print(f"  {model}: {listing.title[:40]}: {error}")
                return None

    try:
        return list(await asyncio.gather(*(one(item) for item in listings)))
    finally:
        await completer.aclose()


def _summary(name: str, results: list[Enrichment | None]) -> None:
    ok = [r for r in results if r is not None and r.is_relevant]
    groups = [len(r.lebenslagen) for r in ok]
    print(
        f"{name}: {len(ok)} relevant of {len(results)}; "
        f"avg {sum(groups) / max(len(ok), 1):.1f} groups/card, "
        f"{sum(1 for g in groups if g == 0)} with none, "
        f"{sum(1 for g in groups if g >= 5)} with 5+"
    )


async def main(model_a: str, model_b: str, count: int) -> None:
    database = Database(get_settings().database_url)
    try:
        async with database.session_factory() as session:
            records = (
                (
                    await session.execute(
                        select(OpportunityRecord)
                        .where(
                            OpportunityRecord.active.is_(True),
                            OpportunityRecord.is_relevant.is_(True),
                        )
                        .order_by(OpportunityRecord.id)
                    )
                )
                .scalars()
                .all()
            )
    finally:
        await database.close()

    step = max(len(records) // count, 1)
    sample = records[::step][:count]
    listings = [_listing(record) for record in sample]

    results_a, results_b = await asyncio.gather(
        _run(model_a, listings), _run(model_b, listings)
    )

    for listing, a, b in zip(listings, results_a, results_b, strict=True):
        print(f"\n{listing.title[:90]}")
        for name, result in ((model_a, a), (model_b, b)):
            if result is None or not result.is_relevant:
                print(f"  {name[:16]:16} (not relevant / failed)")
                continue
            print(f"  {name[:16]:16} tags: {', '.join(result.affected_tags) or '-'}")
            if not result.lebenslagen:
                print(f"  {'':16} groups: []")
            for lebenslage_id, reason in result.lebenslagen_gruende.items():
                print(f"  {'':16} - {lebenslage_id}: {reason}")
            if result.lebenslage_frei:
                print(f"  {'':16} missing group: {result.lebenslage_frei}")

    print()
    _summary(model_a, results_a)
    _summary(model_b, results_b)


if __name__ == "__main__":
    model_a, model_b = sys.argv[1], sys.argv[2]
    asyncio.run(main(model_a, model_b, int(sys.argv[3]) if len(sys.argv) > 3 else 30))
