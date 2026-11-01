"""Opportunity ingestion: registries -> policy steps -> store -> enrichment.

    collect(sources)          read every registry, failures isolated
    steps.default_steps       coverage, actionable, not expired, dedupe
    store.sync                mirror into the table, deactivate vanished
    enrich pending            only new or changed listings cost an LLM call
    store.save_enrichment     one commit per result, so progress survives

The pipeline depends on protocols only (sources, detail readers, enricher,
store); wiring real implementations happens in `services/ingestion.py`.
Trigger-based: nothing here schedules itself.
"""

import asyncio
import logging
from collections.abc import Collection, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID

from meinimpact.infrastructure.ai.listing_enricher import Enrichment
from meinimpact.infrastructure.listings import steps
from meinimpact.infrastructure.listings.collector import collect
from meinimpact.infrastructure.listings.model import Listing
from meinimpact.infrastructure.listings.source import DetailReader, ListingSource
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PendingEnrichment,
    SyncResult,
)

logger = logging.getLogger(__name__)


class Enricher(Protocol):
    async def enrich(self, listing: Listing, detail: str | None) -> Enrichment: ...


class OpportunityStore(Protocol):
    async def sync(
        self,
        listings: Sequence[Listing],
        *,
        complete_source_ids: Collection[str],
        observed_at: datetime,
    ) -> SyncResult: ...

    async def save_enrichment(
        self,
        opportunity_id: UUID,
        enrichment: Enrichment,
        *,
        input_hash: str,
        enriched_at: datetime,
    ) -> None: ...

    async def commit(self) -> None: ...


@dataclass
class IngestionSummary:
    listed: int = 0
    kept: int = 0
    inserted: int = 0
    updated: int = 0
    deactivated: int = 0
    enriched: int = 0
    relevant: int = 0
    failed_sources: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


async def run_ingestion(
    *,
    sources: Sequence[ListingSource],
    detail_readers: Mapping[str, DetailReader],
    enricher: Enricher,
    store: OpportunityStore,
    observed_at: datetime | None = None,
    max_concurrency: int = 4,
) -> IngestionSummary:
    observed_at = observed_at or datetime.now(UTC)
    summary = IngestionSummary()

    report = await collect(sources, observed_at=observed_at)
    summary.listed = len(report.listings)
    summary.failed_sources = [f"{o.source}: {o.error}" for o in report.failed]

    kept = steps.apply(report.listings, steps.default_steps(observed_at.date()))
    summary.kept = len(kept)

    synced = await store.sync(
        kept, complete_source_ids=report.complete_source_ids, observed_at=observed_at
    )
    await store.commit()
    summary.inserted = synced.inserted
    summary.updated = synced.updated
    summary.deactivated = synced.deactivated

    semaphore = asyncio.Semaphore(max_concurrency)

    async def enrich(item: PendingEnrichment) -> Enrichment | None:
        async with semaphore:
            detail = await _read_detail(item.listing, detail_readers, summary.errors)
            try:
                return await enricher.enrich(item.listing, detail)
            except Exception as exc:  # isolation boundary: one listing
                summary.errors.append(f"enrich {item.listing.url}: {exc}")
                return None

    results = await asyncio.gather(*(enrich(item) for item in synced.pending))
    for item, enrichment in zip(synced.pending, results, strict=True):
        if enrichment is None:
            continue  # stays pending, retried next run
        await store.save_enrichment(
            item.opportunity_id,
            enrichment,
            input_hash=item.input_hash,
            enriched_at=datetime.now(UTC),
        )
        await store.commit()
        summary.enriched += 1
        summary.relevant += enrichment.is_relevant

    logger.info("Ingestion finished: %s", summary)
    return summary


async def _read_detail(
    listing: Listing, readers: Mapping[str, DetailReader], errors: list[str]
) -> str | None:
    reader = readers.get(listing.source_id)
    if reader is None:
        return None
    try:
        return await reader.read(listing)
    except Exception as exc:  # enrichment still works from the listing alone
        errors.append(f"detail {listing.url}: {exc}")
        return None
