"""PostgresOpportunityRepository against the real database.

Uses the rolled-back `db_session` fixture; the repository never commits by
itself, so nothing leaks between tests.
"""

import uuid
from dataclasses import replace
from datetime import UTC, date, datetime, timedelta

import pytest
from listing_fakes import NOW, make_listing
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.ai.listing_enricher import Enrichment
from meinimpact.infrastructure.listings.model import Region
from meinimpact.infrastructure.models import OpportunityRecord, SupportSnapshotRecord
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    EXPERT_ONLY_MAX_ACCESSIBILITY,
    EXPERT_ONLY_MAX_EVERYDAY_RELEVANCE,
    PostgresOpportunityRepository,
)

LATER = NOW + timedelta(days=2)
TODAY = date(2026, 11, 1)


def _relevant(
    region: Region = Region.DRESDEN,
    *,
    everyday_relevance: int = 4,
    accessibility: int = 5,
) -> Enrichment:
    return Enrichment(
        is_relevant=True,
        reason="Petition",
        region=region,
        everyday_relevance=everyday_relevance,
        accessibility=accessibility,
        title="Soll die Kita bleiben?",
        summary="Eine Kita soll schließen.",
        affected_tags=("Familie/Kinder",),
        pro_argumente=("Plätze",),
        personal_impact_snippets={"hat_kinder:true": "Betrifft dich."},
    )


async def _record(session: AsyncSession, external_id: str) -> OpportunityRecord:
    result = await session.execute(
        select(OpportunityRecord).where(OpportunityRecord.external_id == external_id)
    )
    return result.scalar_one()


async def test_sync_inserts_new_listings_as_pending(db_session: AsyncSession) -> None:
    repository = PostgresOpportunityRepository(db_session)

    result = await repository.sync(
        [make_listing("a", support_count=10), make_listing("b")],
        complete_source_ids={"src"},
        observed_at=NOW,
    )

    assert (result.inserted, result.updated, result.deactivated) == (2, 0, 0)
    assert {p.listing.external_id for p in result.pending} == {"a", "b"}
    record = await _record(db_session, "a")
    assert record.active
    assert record.first_seen_at == NOW
    assert record.support_count == 10
    assert record.is_relevant is None


async def test_unchanged_enriched_listing_is_not_pending_again(
    db_session: AsyncSession,
) -> None:
    repository = PostgresOpportunityRepository(db_session)
    first = await repository.sync(
        [make_listing("a")], complete_source_ids={"src"}, observed_at=NOW
    )
    [pending] = first.pending
    await repository.save_enrichment(
        pending.opportunity_id,
        _relevant(),
        input_hash=pending.input_hash,
        enriched_at=NOW,
    )

    again = await repository.sync(
        [make_listing("a")], complete_source_ids={"src"}, observed_at=LATER
    )
    changed = await repository.sync(
        [make_listing("a", title="Neuer Titel")],
        complete_source_ids={"src"},
        observed_at=LATER,
    )

    assert (again.inserted, again.updated, again.pending) == (0, 1, ())
    assert [p.listing.title for p in changed.pending] == ["Neuer Titel"]
    record = await _record(db_session, "a")
    assert record.first_seen_at == NOW
    assert record.last_seen_at == LATER


async def test_vanished_listings_are_deactivated_only_for_complete_registries(
    db_session: AsyncSession,
) -> None:
    repository = PostgresOpportunityRepository(db_session)
    await repository.sync(
        [make_listing("a"), make_listing("b", source_id="other")],
        complete_source_ids={"src", "other"},
        observed_at=NOW,
    )

    result = await repository.sync([], complete_source_ids={"src"}, observed_at=LATER)

    assert result.deactivated == 1
    assert not (await _record(db_session, "a")).active
    assert (await _record(db_session, "b")).active  # "other" was not read fully


async def test_support_counts_are_snapshotted_per_run(db_session: AsyncSession) -> None:
    repository = PostgresOpportunityRepository(db_session)
    for observed_at, count in ((NOW, 10), (LATER, 25)):
        await repository.sync(
            [make_listing("a", support_count=count)],
            complete_source_ids={"src"},
            observed_at=observed_at,
        )

    record = await _record(db_session, "a")
    snapshots = await db_session.execute(
        select(SupportSnapshotRecord.observed_at, SupportSnapshotRecord.support_count)
        .where(SupportSnapshotRecord.opportunity_id == record.id)
        .order_by(SupportSnapshotRecord.observed_at)
    )
    assert snapshots.all() == [(NOW, 10), (LATER, 25)]
    assert record.support_count == 25


async def test_list_open_serves_relevant_active_unexpired_except_expert_only(
    db_session: AsyncSession,
) -> None:
    repository = PostgresOpportunityRepository(db_session)
    listings = [
        make_listing("open"),
        replace(make_listing("expired"), closes_on=date(2026, 10, 31)),
        replace(make_listing("closing-today"), closes_on=TODAY),
        make_listing("noise"),
        make_listing("niche"),
        make_listing("expert-only"),
        make_listing("unenriched"),
    ]
    synced = await repository.sync(
        listings, complete_source_ids={"src"}, observed_at=NOW
    )
    special = {
        "noise": Enrichment(is_relevant=False, reason="Besichtigung"),
        # little everyday relevance, but understandable: still served
        "niche": _relevant(everyday_relevance=1, accessibility=3),
        "expert-only": _relevant(
            everyday_relevance=EXPERT_ONLY_MAX_EVERYDAY_RELEVANCE,
            accessibility=EXPERT_ONLY_MAX_ACCESSIBILITY,
        ),
    }
    for pending in synced.pending:
        if pending.listing.external_id == "unenriched":
            continue
        enrichment = special.get(pending.listing.external_id, _relevant())
        await repository.save_enrichment(
            pending.opportunity_id,
            enrichment,
            input_hash=pending.input_hash,
            enriched_at=NOW,
        )

    # Scoped to this test's rows: a local dev DB may hold real ingested data.
    opportunities = [
        o
        for o in await repository.list_open(TODAY)
        if o.source_url.startswith("https://example.org/")
    ]

    assert sorted(o.source_url.rsplit("/", 1)[-1] for o in opportunities) == [
        "closing-today",
        "niche",
        "open",
    ]
    opportunity = next(o for o in opportunities if o.source_url.endswith("/open"))
    assert opportunity.title == "Soll die Kita bleiben?"
    assert opportunity.region == "dresden"
    assert opportunity.source_org == "src"  # unknown registry: id as name
    assert opportunity.personal_impact_snippets == {"hat_kinder:true": "Betrifft dich."}


async def test_save_enrichment_for_unknown_id_raises(db_session: AsyncSession) -> None:
    repository = PostgresOpportunityRepository(db_session)
    with pytest.raises(LookupError):
        await repository.save_enrichment(
            uuid.uuid4(),
            _relevant(),
            input_hash="x",
            enriched_at=datetime.now(UTC),
        )
