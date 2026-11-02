"""PostgreSQL persistence for registry-sourced opportunities.

Write side, used by the ingestion pipeline:
- `sync()` mirrors one run's listings into the table: inserts new registry
  entries, refreshes facts of known ones, records support snapshots, and
  deactivates entries their registry no longer lists (only for registries
  read completely this run). It reports which rows need enrichment: new
  ones and those whose registry text changed.
- `save_enrichment()` stores one enrichment result.

Read side: `list_open()` serves the feed, applying the feed policy below.

The repository never commits; the caller owns the transaction boundaries.
"""

import uuid
from collections.abc import Collection, Sequence
from dataclasses import dataclass
from datetime import date, datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.domain.entities import Opportunity
from meinimpact.infrastructure.ai.listing_enricher import (
    Enrichment,
    enrichment_input_hash,
)
from meinimpact.infrastructure.listings.catalog import SOURCE_NAMES
from meinimpact.infrastructure.listings.model import Listing
from meinimpact.infrastructure.models import OpportunityRecord, SupportSnapshotRecord

# Feed policy: only expert-only items are withheld, i.e. both hardly any
# everyday relevance AND hard to grasp (e.g. EU rules on trailer CO2
# accounting). Everything else is served; the app ranks by these scores.
# Applied at read time, so tuning needs no re-enrichment.
EXPERT_ONLY_MAX_EVERYDAY_RELEVANCE = 1
EXPERT_ONLY_MAX_ACCESSIBILITY = 2


@dataclass(frozen=True, slots=True)
class PendingEnrichment:
    opportunity_id: uuid.UUID
    listing: Listing
    input_hash: str


@dataclass(frozen=True, slots=True)
class SyncResult:
    inserted: int
    updated: int
    deactivated: int
    pending: tuple[PendingEnrichment, ...]


class PostgresOpportunityRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def commit(self) -> None:
        await self._session.commit()

    async def sync(
        self,
        listings: Sequence[Listing],
        *,
        complete_source_ids: Collection[str],
        observed_at: datetime,
    ) -> SyncResult:
        source_ids = {listing.source_id for listing in listings} | set(
            complete_source_ids
        )
        existing = await self._records_for(source_ids)
        seen: set[tuple[str, str]] = set()
        pending: list[PendingEnrichment] = []
        snapshots: list[SupportSnapshotRecord] = []
        inserted = updated = 0

        for listing in listings:
            if listing.key in seen:
                continue
            seen.add(listing.key)
            record = existing.get(listing.key)
            if record is None:
                record = _new_record(listing, observed_at)
                self._session.add(record)
                inserted += 1
            else:
                updated += 1
            _apply_facts(record, listing, observed_at)
            if listing.support.count is not None:
                snapshots.append(
                    SupportSnapshotRecord(
                        opportunity_id=record.id,
                        observed_at=observed_at,
                        support_count=listing.support.count,
                    )
                )
            input_hash = enrichment_input_hash(listing)
            if record.enrichment_input_hash != input_hash:
                pending.append(PendingEnrichment(record.id, listing, input_hash))

        deactivated = 0
        for key, record in existing.items():
            if record.active and key not in seen and key[0] in complete_source_ids:
                record.active = False
                deactivated += 1

        await self._session.flush()  # opportunities exist before their snapshots
        self._session.add_all(snapshots)
        await self._session.flush()
        return SyncResult(inserted, updated, deactivated, tuple(pending))

    async def save_enrichment(
        self,
        opportunity_id: uuid.UUID,
        enrichment: Enrichment,
        *,
        input_hash: str,
        enriched_at: datetime,
    ) -> None:
        record = await self._session.get(OpportunityRecord, opportunity_id)
        if record is None:
            raise LookupError(f"opportunity {opportunity_id} not found")
        record.enrichment_input_hash = input_hash
        record.enriched_at = enriched_at
        record.is_relevant = enrichment.is_relevant
        record.relevance_reason = enrichment.reason
        record.region = enrichment.region.value if enrichment.region else None
        record.everyday_relevance = enrichment.everyday_relevance
        record.accessibility = enrichment.accessibility
        record.free_topic = enrichment.free_topic or None
        record.topic_candidate = enrichment.topic_candidate or None
        record.districts = list(enrichment.districts)
        record.title = enrichment.title or None
        record.summary = enrichment.summary or None
        record.affected_tags = list(enrichment.affected_tags)
        record.lebenslagen = list(enrichment.lebenslagen)
        record.lebenslage_frei = enrichment.lebenslage_frei or None
        record.werte_relevanz = dict(enrichment.werte_relevanz)
        record.pro_argumente = list(enrichment.pro_argumente)
        record.contra_argumente = list(enrichment.contra_argumente)
        record.personal_impact_snippets = dict(enrichment.personal_impact_snippets)
        await self._session.flush()

    async def list_open(self, today: date) -> list[Opportunity]:
        result = await self._session.execute(
            select(OpportunityRecord)
            .where(
                OpportunityRecord.active.is_(True),
                OpportunityRecord.is_relevant.is_(True),
                OpportunityRecord.region.is_not(None),
                or_(
                    OpportunityRecord.everyday_relevance
                    > EXPERT_ONLY_MAX_EVERYDAY_RELEVANCE,
                    OpportunityRecord.accessibility > EXPERT_ONLY_MAX_ACCESSIBILITY,
                ),
                or_(
                    OpportunityRecord.closes_on.is_(None),
                    OpportunityRecord.closes_on >= today,
                ),
            )
            .order_by(OpportunityRecord.first_seen_at.desc())
        )
        return [_to_domain(record) for record in result.scalars().all()]

    async def _records_for(
        self, source_ids: Collection[str]
    ) -> dict[tuple[str, str], OpportunityRecord]:
        if not source_ids:
            return {}
        result = await self._session.execute(
            select(OpportunityRecord).where(OpportunityRecord.source_id.in_(source_ids))
        )
        return {(r.source_id, r.external_id): r for r in result.scalars().all()}


def _new_record(listing: Listing, observed_at: datetime) -> OpportunityRecord:
    return OpportunityRecord(
        id=uuid.uuid4(),
        source_id=listing.source_id,
        external_id=listing.external_id,
        first_seen_at=observed_at,
        affected_tags=[],
        lebenslagen=[],
        districts=[],
        werte_relevanz={},
        pro_argumente=[],
        contra_argumente=[],
        personal_impact_snippets={},
    )


def _apply_facts(
    record: OpportunityRecord, listing: Listing, observed_at: datetime
) -> None:
    record.source_url = listing.url
    record.kind = listing.kind.value
    record.status = listing.status.value
    record.registry_region = listing.region.value if listing.region else None
    record.locality = listing.locality
    record.organizer = listing.organizer
    record.registry_title = listing.title
    record.registry_summary = listing.summary
    record.source_labels = list(listing.source_labels)
    record.opens_on = listing.opens_on
    record.closes_on = listing.closes_on
    if listing.support.count is not None:
        record.support_count = listing.support.count
        record.support_count_as_of = observed_at
    record.support_goal = listing.support.goal
    record.last_seen_at = observed_at
    record.active = True


def _to_domain(record: OpportunityRecord) -> Opportunity:
    return Opportunity(
        id=record.id,
        source_org=SOURCE_NAMES.get(record.source_id, record.source_id),
        source_url=record.source_url,
        kind=record.kind,
        status=record.status,
        region=record.region or "",
        locality=record.locality,
        organizer=record.organizer,
        title=record.title or record.registry_title,
        summary=record.summary or record.registry_summary or "",
        affected_tags=tuple(record.affected_tags),
        lebenslagen=tuple(record.lebenslagen),
        werte_relevanz=dict(record.werte_relevanz),
        pro_argumente=tuple(record.pro_argumente),
        contra_argumente=tuple(record.contra_argumente),
        personal_impact_snippets=dict(record.personal_impact_snippets),
        everyday_relevance=record.everyday_relevance,
        accessibility=record.accessibility,
        districts=tuple(record.districts),
        opens_on=record.opens_on,
        closes_on=record.closes_on,
        support_count=record.support_count,
        support_goal=record.support_goal,
        support_count_as_of=record.support_count_as_of,
        first_seen_at=record.first_seen_at,
    )
