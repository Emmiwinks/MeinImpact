#!/usr/bin/env python3
"""Dry run for one place: what its sources would bring, before it goes live.

Reads every configured source (no DB), keeps the listings of the place and
the places inside it, and prints per source and kind how many survive the
steps, plus portal authorities that name the place but match no place file
(a hint for `portal_names`). With `--enrich N` it also sends up to N kept
listings through the production enrichment, to measure the share that is
relevant and the cost per listing (Mistral, real money: about 1 cent each).

  docker compose exec api python scripts/dryrun_place.py wittenberg --enrich 20
"""

import argparse
import asyncio
import random
from collections import Counter
from collections.abc import Sequence

from meinimpact import places
from meinimpact.core.config import get_settings
from meinimpact.infrastructure.ai.listing_enricher import ListingEnricher
from meinimpact.infrastructure.ai.mistral_json import MistralJsonCompleter
from meinimpact.infrastructure.ai.usage import Price, track
from meinimpact.infrastructure.listings import steps
from meinimpact.infrastructure.listings.catalog import (
    default_detail_readers,
    default_district_matchers,
    default_sources,
)
from meinimpact.infrastructure.listings.collector import SourceOutcome, collect
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import Listing
from meinimpact.services.coverage import CoverageConfig


async def main(place_key: str, enrich: int) -> None:
    place = places.by_key(place_key)
    if place is None:
        raise SystemExit(f"no place file for {place_key!r}")
    inside = {
        p.key
        for p in places.ALL
        if p.depth >= place.depth and p.ags.startswith(place.ags)
    }

    async with PoliteHttpClient() as http:
        report = await collect(default_sources(http))
        kept = [
            item
            for item in steps.apply(
                report.listings, steps.default_steps(report.observed_at.date())
            )
            if item.region in inside
        ]
        print(f"\n{place.name} ({place.level}, {place.status}): {len(kept)} kept")
        _print_counts(report.outcomes, kept)
        _print_unmatched(report.listings, place.name)
        if enrich:
            await _enrich_sample(http, kept, enrich)


def _print_counts(outcomes: Sequence[SourceOutcome], kept: list[Listing]) -> None:
    for outcome in (o for o in outcomes if not o.ok):
        print(f"  SOURCE FAILED {outcome.source}: {outcome.error}")
    print("by source:", dict(Counter(item.source_id for item in kept).most_common()))
    print("by kind:  ", dict(Counter(str(item.kind) for item in kept).most_common()))
    print("by region:", dict(Counter(str(item.region) for item in kept).most_common()))
    config = CoverageConfig()
    print(
        f"targets after enrichment: {config.min_new_per_week} new/week, "
        f"{config.min_kinds} kinds, {config.min_tags} topics, "
        f"<= {config.max_source_share:.0%} from one source"
    )


def _print_unmatched(listings: list[Listing], name: str) -> None:
    unmatched = Counter(
        item.locality
        for item in listings
        if item.region is None and item.locality and name in item.locality
    )
    if unmatched:
        print(f"authorities naming {name!r} but outside coverage:")
        for locality, count in unmatched.most_common(10):
            print(f"  {count:4}  {locality}")


async def _enrich_sample(
    http: PoliteHttpClient, kept: list[Listing], size: int
) -> None:
    settings = get_settings()
    if not settings.mistral_api_key:
        raise SystemExit("MEINIMPACT_MISTRAL_API_KEY is not set")
    completer = MistralJsonCompleter(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=settings.mistral_extraction_model,
    )
    enricher = ListingEnricher(completer, default_district_matchers())
    readers = default_detail_readers(http)
    price = Price(
        settings.mistral_extraction_eur_per_m_input,
        settings.mistral_extraction_eur_per_m_output,
    )
    sample = random.sample(kept, min(size, len(kept)))
    relevant: list[Listing] = []
    try:
        with track() as usage:
            for item in sample:
                reader = readers.get(item.source_id)
                detail = await reader.read(item) if reader else None
                enrichment = await enricher.enrich(item, detail)
                mark = "+" if enrichment.is_relevant else "-"
                print(f"  {mark} {item.title[:70]}  ({enrichment.reason[:60]})")
                if enrichment.is_relevant:
                    relevant.append(item)
    finally:
        await completer.aclose()
    if sample:
        cost = price.cost(usage)
        print(
            f"relevant: {len(relevant)}/{len(sample)}; {cost:.2f} € for the sample, "
            f"{cost / len(sample):.3f} € per listing; enriching all "
            f"{len(kept)} kept once: about {cost / len(sample) * len(kept):.2f} €"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("place")
    parser.add_argument("--enrich", type=int, default=0)
    args = parser.parse_args()
    asyncio.run(main(args.place, args.enrich))
