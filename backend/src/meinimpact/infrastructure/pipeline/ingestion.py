"""Opportunity ingestion: registries -> policy steps -> store -> enrichment.

    collect(sources)          read every registry, failures isolated
    steps.default_steps       coverage, actionable, not expired, dedupe
    store.sync                mirror into the table, deactivate vanished
    enrich pending            only new or changed listings cost an LLM call,
                              and only while the run's budget lasts
    store.save_enrichment     one commit per result, so progress survives
    bundle                    opportunities on one matter become one card;
                              only new or changed bundles are described

Every source instance gets its own row in the summary (fetched, kept,
enriched, Mistral tokens and euros), so /admin and the drift check see each
registry on its own.

The pipeline depends on protocols only (sources, detail readers, enricher,
store); wiring real implementations happens in `services/ingestion.py`.
Trigger-based: nothing here schedules itself.
"""

import asyncio
import logging
from collections.abc import Collection, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from typing import Protocol, runtime_checkable
from uuid import UUID

from meinimpact.infrastructure.ai.bundler import (
    Bundle,
    BundleItem,
    allowed,
    bundle_input_hash,
)
from meinimpact.infrastructure.ai.listing_enricher import Enrichment
from meinimpact.infrastructure.ai.usage import Price, Usage
from meinimpact.infrastructure.ai.usage import track as track_usage
from meinimpact.infrastructure.listings import steps
from meinimpact.infrastructure.listings.collector import collect
from meinimpact.infrastructure.listings.model import Listing
from meinimpact.infrastructure.listings.source import DetailReader, ListingSource
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PendingEnrichment,
    SyncResult,
)

logger = logging.getLogger(__name__)

# A log line every this many saved enrichments, so a long run shows progress
_PROGRESS_EVERY = 25


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


@runtime_checkable
class BundleStore(Protocol):
    async def bundle_items(self, today: date) -> list[BundleItem]: ...

    async def save_bundles(
        self,
        today: date,
        *,
        described: Sequence[tuple[Bundle, str]],
        kept: Collection[UUID],
    ) -> None: ...


class BundleWriter(Protocol):
    async def propose_groups(
        self, items: Sequence[BundleItem]
    ) -> list[list[BundleItem]]: ...

    async def describe(
        self, items: Sequence[BundleItem], details: Sequence[str | None]
    ) -> Bundle | None: ...


@dataclass(frozen=True, slots=True)
class RunBudget:
    """What one run may spend on Mistral. Listings left when it is reached
    stay pending and are enriched by the next run; bundling waits too."""

    price: Price
    max_eur: float


@dataclass
class SourceStats:
    """One configured source instance in one run (e.g. openPetition's
    Dresden page). `pending` counts its new or changed listings, `deferred`
    those the budget left for the next run."""

    source: str
    source_id: str
    fetched: int = 0
    kept: int = 0
    pending: int = 0
    enriched: int = 0
    relevant: int = 0
    deferred: int = 0
    duration_s: float = 0.0
    error: str | None = None
    calls: int = 0
    prompt_tokens: int = 0
    completion_tokens: int = 0
    cost_eur: float = 0.0


@dataclass
class IngestionSummary:
    listed: int = 0
    kept: int = 0
    inserted: int = 0
    updated: int = 0
    deactivated: int = 0
    enriched: int = 0
    relevant: int = 0
    # Left pending because the run's budget was spent
    deferred: int = 0
    budget_reached: bool = False
    # Cards that bundle several opportunities after this run
    bundles: int = 0
    # Mistral use of the whole run, bundling included
    calls: int = 0
    prompt_tokens: int = 0
    completion_tokens: int = 0
    cost_eur: float = 0.0
    # Council members stored by the weekly member sync; 0 when it did not run
    council_members: int = 0
    # ISO timestamp of the stored members, also when this run skipped the sync
    council_members_synced_at: str | None = None
    failed_sources: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    sources: list[SourceStats] = field(default_factory=list)
    # Sources that behave unlike their own recent runs (filled after the run)
    drift: list[str] = field(default_factory=list)
    # Letter addresses missing or no longer on their source page (weekly)
    contacts: list[str] = field(default_factory=list)


async def run_ingestion(
    *,
    sources: Sequence[ListingSource],
    detail_readers: Mapping[str, DetailReader],
    enricher: Enricher,
    store: OpportunityStore,
    bundler: BundleWriter | None = None,
    budget: RunBudget | None = None,
    observed_at: datetime | None = None,
    max_concurrency: int = 4,
) -> IngestionSummary:
    with track_usage() as run_usage:
        summary = await _run(
            sources=sources,
            detail_readers=detail_readers,
            enricher=enricher,
            store=store,
            bundler=bundler,
            budget=budget,
            observed_at=observed_at or datetime.now(UTC),
            max_concurrency=max_concurrency,
            run_usage=run_usage,
        )
    summary.calls = run_usage.calls
    summary.prompt_tokens = run_usage.prompt_tokens
    summary.completion_tokens = run_usage.completion_tokens
    if budget is not None:
        summary.cost_eur = round(budget.price.cost(run_usage), 4)
    logger.info("Ingestion finished: %s", summary)
    return summary


async def _run(
    *,
    sources: Sequence[ListingSource],
    detail_readers: Mapping[str, DetailReader],
    enricher: Enricher,
    store: OpportunityStore,
    bundler: BundleWriter | None,
    budget: RunBudget | None,
    observed_at: datetime,
    max_concurrency: int,
    run_usage: Usage,
) -> IngestionSummary:
    summary = IngestionSummary()

    def over_budget() -> bool:
        return budget is not None and budget.price.cost(run_usage) >= budget.max_eur

    report = await collect(sources, observed_at=observed_at)
    summary.listed = len(report.listings)
    summary.failed_sources = [f"{o.source}: {o.error}" for o in report.failed]
    stats = {
        o.source: SourceStats(
            source=o.source,
            source_id=o.source_id,
            fetched=len(o.listings),
            duration_s=round(o.duration_s, 1),
            error=o.error,
        )
        for o in report.outcomes
    }
    summary.sources = list(stats.values())
    # Which source instance a listing came from: the same registry entry can
    # come from several instances (openPetition's Sachsen and Dresden pages),
    # and dedupe keeps the one with the most specific region
    origin = {
        (*listing.key, listing.region): o.source
        for o in report.outcomes
        for listing in o.listings
    }

    def stats_of(listing: Listing) -> SourceStats | None:
        source = origin.get((*listing.key, listing.region))
        return stats.get(source) if source else None

    kept = steps.apply(report.listings, steps.default_steps(observed_at.date()))
    summary.kept = len(kept)
    for listing in kept:
        if row := stats_of(listing):
            row.kept += 1

    synced = await store.sync(
        kept, complete_source_ids=report.complete_source_ids, observed_at=observed_at
    )
    await store.commit()
    summary.inserted = synced.inserted
    summary.updated = synced.updated
    summary.deactivated = synced.deactivated
    for item in synced.pending:
        if row := stats_of(item.listing):
            row.pending += 1

    semaphore = asyncio.Semaphore(max_concurrency)
    # The store holds one session: saves take turns while enrichment runs on
    save_lock = asyncio.Lock()
    total = len(synced.pending)

    async def enrich_and_save(item: PendingEnrichment) -> None:
        row = stats_of(item.listing)
        async with semaphore:
            if over_budget():
                summary.deferred += 1
                summary.budget_reached = True
                if row:
                    row.deferred += 1
                return  # stays pending, enriched by the next run
            detail = await _read_detail(item.listing, detail_readers, summary.errors)
            with track_usage() as item_usage:
                try:
                    enrichment = await enricher.enrich(item.listing, detail)
                except Exception as exc:  # isolation boundary: one listing
                    summary.errors.append(f"enrich {item.listing.url}: {exc}")
                    enrichment = None  # stays pending, retried next run
            if row:
                row.calls += item_usage.calls
                row.prompt_tokens += item_usage.prompt_tokens
                row.completion_tokens += item_usage.completion_tokens
                if budget is not None:
                    row.cost_eur = round(
                        row.cost_eur + budget.price.cost(item_usage), 4
                    )
            if enrichment is None:
                return
        # Saved as soon as it is done, so a restart mid-run (a deploy, a full
        # re-enrichment after a version bump) only loses what was in flight
        async with save_lock:
            await store.save_enrichment(
                item.opportunity_id,
                enrichment,
                input_hash=item.input_hash,
                enriched_at=datetime.now(UTC),
            )
            await store.commit()
        summary.enriched += 1
        summary.relevant += enrichment.is_relevant
        if row:
            row.enriched += 1
            row.relevant += enrichment.is_relevant
        if summary.enriched % _PROGRESS_EVERY == 0:
            logger.info("Enriched %d of %d", summary.enriched, total)

    if total:
        logger.info("Enriching %d listings", total)
    await asyncio.gather(*(enrich_and_save(item) for item in synced.pending))

    if over_budget():
        summary.budget_reached = True
    elif bundler is not None and isinstance(store, BundleStore):
        listings = {listing.key: listing for listing in kept}
        try:
            summary.bundles = await _bundle(
                store, bundler, listings, detail_readers, observed_at.date(), summary
            )
            await store.commit()
        except Exception as exc:  # cards stay as they were
            summary.errors.append(f"bundle: {exc}")
    return summary


async def _bundle(
    store: BundleStore,
    bundler: BundleWriter,
    listings: Mapping[tuple[str, str], Listing],
    detail_readers: Mapping[str, DetailReader],
    today: date,
    summary: IngestionSummary,
) -> int:
    """Keeps every unchanged bundle, describes new and changed ones.

    Existing bundles are proposed again on their own, so a bundle never
    depends on the list pass finding it a second time; only items in no
    bundle go to that pass.
    """
    items = await store.bundle_items(today)
    existing: dict[UUID, list[BundleItem]] = {}
    for item in items:
        if item.bundle_id is not None:
            existing.setdefault(item.bundle_id, []).append(item)

    kept: set[UUID] = set()
    candidates: list[list[BundleItem]] = []
    for members in existing.values():
        unchanged = len(members) >= 2 and all(
            m.bundle_input_hash == bundle_input_hash(members) for m in members
        )
        if unchanged:
            kept.update(m.id for m in members)
        else:
            candidates.append(members)
    taken = kept | {m.id for group in candidates for m in group}
    candidates += await bundler.propose_groups([i for i in items if i.id not in taken])

    described: list[tuple[Bundle, str]] = []
    for group in candidates:
        if not allowed(group):
            continue
        details = [
            await _read_detail(listings[i.key], detail_readers, summary.errors)
            if i.key in listings
            else None
            for i in group
        ]
        bundle = await bundler.describe(group, details)
        if bundle is None:
            continue
        members = [i for i in group if i.id in bundle.options]
        described.append((bundle, bundle_input_hash(members)))

    await store.save_bundles(today, described=described, kept=kept)
    return len(described) + len({i.bundle_id for i in items if i.id in kept})


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
