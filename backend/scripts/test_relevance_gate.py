#!/usr/bin/env python3
"""Would a cheap relevance gate lose cards? Measures before deciding.

Runs the same listings through
  reference  mistral-medium, full production prompt (its verdict counts)
  gate       mistral-small, a short gate prompt
  control    mistral-medium, the same short gate prompt
and prints the gate's misses (relevant cards it would drop), its false
passes, and tokens and euros per listing. The gate prompt is cut out of the
production prompt (relevance and scope rules only), so there is no second
copy of those rules. Nothing is written to the DB.

Listings: a deterministic sample of stored opportunities (any verdict) plus
council papers from a saved OParl dry run, each with the detail text the
pipeline would read. Costs about 2 € at the default size.

  docker compose exec api python scripts/test_relevance_gate.py --db 110 --council 40
"""

import argparse
import asyncio
import json
from dataclasses import dataclass
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import select

from meinimpact.core.config import get_settings
from meinimpact.infrastructure.ai.listing_enricher import (
    _SCOPES,
    build_prompt,
    parse_enrichment,
)
from meinimpact.infrastructure.ai.mistral_json import MistralJsonCompleter
from meinimpact.infrastructure.ai.usage import Price, Usage, track
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.listings.catalog import default_detail_readers
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import (
    ActionKind,
    Listing,
    ListingStatus,
)
from meinimpact.infrastructure.models import OpportunityRecord

_COUNCIL_RUN = (
    Path(__file__).parent / "dryrun_output" / "decisions_20261108_162907.json"
)
_CONCURRENCY = 4
_GATE_SCHEMA = """{
  "is_participation": <bool>,
  "reason": "<ein kurzer Satz, warum (nicht)>",
  "scope": <wie unten beschrieben>
}

"""


def gate_prompt(listing: Listing, detail: str | None) -> str:
    """The production prompt without everything after the scope rules, and
    with a schema of only the three fields the gate decides."""
    full = build_prompt(listing, detail)
    head, _, rest = full.partition(
        "antworte NUR mit JSON in genau dieser Struktur:\n\n"
    )
    rules = rest[rest.index("is_participation = true NUR") :]
    rules = rules[: rules.index("reichweite und orte =")]
    entry = full[full.rindex("Eintrag:\n") :]
    return f"{head}antworte NUR mit JSON in genau dieser Struktur:\n\n{_GATE_SCHEMA}{rules}{entry}"


def _relevant_by_gate(raw: dict[str, Any]) -> bool:
    scope = str(raw.get("scope") or "").strip().lower()
    return raw.get("is_participation") is True and _SCOPES.get(scope) is not None


@dataclass
class Verdicts:
    reference: bool | None = None
    gate: bool | None = None
    control: bool | None = None


def _record_listing(record: OpportunityRecord) -> Listing:
    return Listing(
        source_id=record.source_id,
        external_id=record.external_id,
        url=record.source_url,
        title=record.registry_title,
        kind=ActionKind(record.kind),
        status=ListingStatus(record.status),
        region=record.registry_region,
        observed_at=datetime.now(UTC),
        locality=record.locality,
        organizer=record.organizer,
        summary=record.registry_summary,
        opens_on=record.opens_on,
        closes_on=record.closes_on,
        source_labels=tuple(record.source_labels or ()),
    )


def _council_listing(raw: dict[str, Any]) -> Listing:
    def day(value: str | None) -> date | None:
        return date.fromisoformat(value) if value else None

    return Listing(
        source_id=raw["source_id"],
        external_id=raw["external_id"],
        url=raw["url"],
        title=raw["title"],
        kind=ActionKind(raw["kind"]),
        status=ListingStatus(raw["status"]),
        region=raw["region"],
        observed_at=datetime.now(UTC),
        locality=raw.get("locality"),
        organizer=raw.get("organizer"),
        summary=raw.get("summary"),
        opens_on=day(raw.get("opens_on")),
        closes_on=day(raw.get("closes_on")),
        source_labels=tuple(raw.get("source_labels") or ()),
        recipient_bodies=tuple(raw.get("recipient_bodies") or ()),
    )


async def _sample(db_count: int, council_count: int) -> list[Listing]:
    database = Database(get_settings().database_url)
    try:
        async with database.session_factory() as session:
            records = (
                (
                    await session.execute(
                        select(OpportunityRecord)
                        .where(OpportunityRecord.is_relevant.is_not(None))
                        .order_by(OpportunityRecord.id)
                    )
                )
                .scalars()
                .all()
            )
    finally:
        await database.close()
    step = max(len(records) // max(db_count, 1), 1)
    stored = [_record_listing(r) for r in records[::step][:db_count]]
    rows = json.loads(_COUNCIL_RUN.read_text(encoding="utf-8"))
    step = max(len(rows) // max(council_count, 1), 1)
    council = [_council_listing(row["listing"]) for row in rows[::step][:council_count]]
    return stored + council


async def _details(http: PoliteHttpClient, listings: list[Listing]) -> list[str | None]:
    readers = default_detail_readers(http)
    details: list[str | None] = []
    for listing in listings:
        reader = readers.get(listing.source_id)
        try:
            details.append(await reader.read(listing) if reader else None)
        except Exception as error:  # the listing alone still decides
            print(f"  detail failed {listing.url}: {type(error).__name__}")
            details.append(None)
    return details


async def _run(
    model: str,
    jobs: list[tuple[Listing, str | None]],
    *,
    gate: bool,
) -> tuple[list[bool | None], Usage]:
    settings = get_settings()
    assert settings.mistral_api_key
    completer = MistralJsonCompleter(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=model,
        max_tokens=300 if gate else 1200,
    )
    semaphore = asyncio.Semaphore(_CONCURRENCY)

    async def one(listing: Listing, detail: str | None) -> bool | None:
        async with semaphore:
            try:
                if gate:
                    raw = await completer.complete_json(gate_prompt(listing, detail))
                    return _relevant_by_gate(raw)
                raw = await completer.complete_json(build_prompt(listing, detail))
                return parse_enrichment(raw).is_relevant
            except Exception as error:  # counted as failed, not as a verdict
                print(f"  {model} {'gate' if gate else 'full'}: {error}"[:160])
                return None

    try:
        with track() as usage:
            verdicts = await asyncio.gather(*(one(item, d) for item, d in jobs))
    finally:
        await completer.aclose()
    return list(verdicts), usage


async def main(
    db_count: int, council_count: int, small_in: float, small_out: float
) -> None:
    settings = get_settings()
    if not settings.mistral_api_key:
        raise SystemExit("MEINIMPACT_MISTRAL_API_KEY is not set")
    listings = await _sample(db_count, council_count)
    print(f"{len(listings)} listings; reading detail texts ...", flush=True)
    async with PoliteHttpClient() as http:
        details = await _details(http, listings)
    jobs = list(zip(listings, details, strict=True))

    medium = settings.mistral_extraction_model
    print("running reference, gate and control ...", flush=True)
    (
        (reference, ref_usage),
        (gated, gate_usage),
        (control, ctl_usage),
    ) = await asyncio.gather(
        _run(medium, jobs, gate=False),
        _run("mistral-small-latest", jobs, gate=True),
        _run(medium, jobs, gate=True),
    )

    def compare(name: str, verdicts: list[bool | None]) -> None:
        pairs = [
            (r, v) for r, v in zip(reference, verdicts, strict=True) if r is not None
        ]
        misses = [
            listing
            for listing, r, v in zip(listings, reference, verdicts, strict=True)
            if r is True and v is False
        ]
        passes = sum(1 for r, v in pairs if r is False and v is True)
        failed = sum(1 for r, v in pairs if v is None)
        relevant = sum(1 for r, _ in pairs if r)
        print(
            f"\n{name}: misses {len(misses)} of {relevant} relevant, "
            f"false passes {passes} of {len(pairs) - relevant} not relevant, "
            f"failed {failed}"
        )
        for listing in misses:
            print(f"  MISSED [{listing.source_id}] {listing.title[:90]}")

    compare("gate (small, short prompt)", gated)
    compare("control (medium, short prompt)", control)

    medium_price = Price(
        settings.mistral_extraction_eur_per_m_input,
        settings.mistral_extraction_eur_per_m_output,
    )
    small_price = Price(small_in, small_out)
    n = len(listings)
    print("\nper listing (main call only):")
    for name, usage, price in (
        ("reference medium full", ref_usage, medium_price),
        ("gate small short", gate_usage, small_price),
        ("control medium short", ctl_usage, medium_price),
    ):
        print(
            f"  {name:22} {usage.prompt_tokens / n:7.0f} in {usage.completion_tokens / n:5.0f}"
            f" out  {price.cost(usage) / n:.4f} €"
        )
    print(f"(small prices assumed: {small_in} / {small_out} € per M tokens; check)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=int, default=110)
    parser.add_argument("--council", type=int, default=40)
    parser.add_argument("--small-in", type=float, default=0.1)
    parser.add_argument("--small-out", type=float, default=0.3)
    args = parser.parse_args()
    asyncio.run(main(args.db, args.council, args.small_in, args.small_out))
