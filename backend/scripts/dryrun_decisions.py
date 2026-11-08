#!/usr/bin/env python3
"""Dry run: upcoming Dresden council decisions through the real enrichment.

Reads the OParl source and each paper's PDF exactly like an ingestion run,
sends every listing through the production enrichment prompt and model, and
reports what would be shown and what is filtered out (with the model's
reason). Nothing is written to the DB; costs one Mistral call per listing.

  docker compose exec api python scripts/dryrun_decisions.py
"""

import asyncio
import json
import sys
from collections import Counter
from dataclasses import asdict
from datetime import UTC, date, datetime
from enum import Enum
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from meinimpact.core.config import get_settings
from meinimpact.infrastructure.ai.listing_enricher import ListingEnricher
from meinimpact.infrastructure.ai.mistral_json import MistralJsonCompleter
from meinimpact.infrastructure.geo.districts import CITIES, DistrictMatcher
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import Listing, Region
from meinimpact.infrastructure.listings.sources.oparl import (
    DRESDEN,
    OParlDetailReader,
    OParlSource,
)

_OUTPUT_DIR = Path(__file__).parent / "dryrun_output"
_CONCURRENCY = 4


def _json_default(value: object) -> object:
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, tuple | frozenset):
        return list(value)
    raise TypeError(f"not JSON serializable: {type(value).__name__}")


async def main() -> None:
    settings = get_settings()
    observed_at = datetime.now(UTC)
    completer = MistralJsonCompleter(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=settings.mistral_extraction_model,
    )
    enricher = ListingEnricher(
        completer, {Region.DRESDEN: DistrictMatcher.for_city(CITIES["dresden"])}
    )
    gate = asyncio.Semaphore(_CONCURRENCY)
    rows: list[dict[str, object]] = []

    try:
        async with PoliteHttpClient() as http:
            print("reading agendas ...", flush=True)
            listings = await OParlSource(http, DRESDEN).fetch(observed_at=observed_at)
            print(
                f"{len(listings)} upcoming papers; reading PDFs + enriching", flush=True
            )
            reader = OParlDetailReader(http, DRESDEN)

            async def one(listing: Listing) -> None:
                async with gate:
                    try:
                        detail = await reader.read(listing)
                    except Exception as error:
                        detail = None
                        print(f"  detail failed {listing.url}: {error}", flush=True)
                    try:
                        enrichment = asdict(await enricher.enrich(listing, detail))
                    except Exception as error:
                        enrichment = {"error": str(error)}
                    rows.append(
                        {
                            "listing": asdict(listing),
                            "paper_type": (detail or "").split("\n", 1)[0],
                            "detail_chars": len(detail or ""),
                            "enrichment": enrichment,
                        }
                    )
                    if len(rows) % 20 == 0:
                        print(f"  {len(rows)}/{len(listings)}", flush=True)

            await asyncio.gather(*(one(item) for item in listings))
    finally:
        await completer.aclose()

    shown = [r for r in rows if r["enrichment"].get("is_relevant")]  # type: ignore[attr-defined]
    print(
        f"\nupcoming papers: {len(rows)}  shown: {len(shown)}  filtered: {len(rows) - len(shown)}"
    )
    print("by body:", Counter(r["listing"]["organizer"] for r in rows).most_common())  # type: ignore[index]

    _OUTPUT_DIR.mkdir(exist_ok=True)
    path = _OUTPUT_DIR / f"decisions_{observed_at:%Y%m%d_%H%M%S}.json"
    path.write_text(
        json.dumps(rows, default=_json_default, ensure_ascii=False, indent=2)
    )
    print(f"wrote {path}")


if __name__ == "__main__":
    asyncio.run(main())
