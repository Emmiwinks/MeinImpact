"""run_ingestion orchestration, against in-memory fakes of every port."""

import uuid
from collections.abc import Collection, Sequence
from datetime import datetime

from listing_fakes import NOW, BrokenSource, StaticSource, make_listing

from meinimpact.infrastructure.ai.listing_enricher import (
    Enrichment,
    enrichment_input_hash,
)
from meinimpact.infrastructure.listings.model import Listing, Region
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PendingEnrichment,
    SyncResult,
)
from meinimpact.infrastructure.pipeline.ingestion import run_ingestion


class FakeStore:
    def __init__(self) -> None:
        self.synced: list[Listing] = []
        self.complete: Collection[str] = ()
        self.saved: dict[uuid.UUID, Enrichment] = {}
        self.commits = 0

    async def sync(
        self,
        listings: Sequence[Listing],
        *,
        complete_source_ids: Collection[str],
        observed_at: datetime,
    ) -> SyncResult:
        self.synced = list(listings)
        self.complete = complete_source_ids
        pending = tuple(
            PendingEnrichment(uuid.uuid4(), item, enrichment_input_hash(item))
            for item in listings
        )
        return SyncResult(
            inserted=len(pending), updated=0, deactivated=1, pending=pending
        )

    async def save_enrichment(
        self,
        opportunity_id: uuid.UUID,
        enrichment: Enrichment,
        *,
        input_hash: str,
        enriched_at: datetime,
    ) -> None:
        self.saved[opportunity_id] = enrichment

    async def commit(self) -> None:
        self.commits += 1


class FakeEnricher:
    def __init__(self, *, fail_for: Collection[str] = ()) -> None:
        self.fail_for = fail_for
        self.details: dict[str, str | None] = {}

    async def enrich(self, listing: Listing, detail: str | None) -> Enrichment:
        if listing.external_id in self.fail_for:
            raise RuntimeError("model timeout")
        self.details[listing.external_id] = detail
        relevant = listing.external_id != "noise"
        return Enrichment(
            is_relevant=relevant,
            reason="ok",
            region=Region.BUND if relevant else None,
            title="Frage?" if relevant else "",
            summary="Text." if relevant else "",
        )


class FakeDetailReader:
    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail

    async def read(self, listing: Listing) -> str | None:
        if self.fail:
            raise ConnectionError("detail page down")
        return f"detail of {listing.external_id}"


async def test_run_syncs_kept_listings_and_enriches_pending_ones() -> None:
    store, enricher = FakeStore(), FakeEnricher()
    source = StaticSource(
        "src",
        [make_listing("a"), make_listing("noise"), make_listing("x", region=None)],
    )

    summary = await run_ingestion(
        sources=[source],
        detail_readers={"src": FakeDetailReader()},
        enricher=enricher,
        store=store,
        observed_at=NOW,
    )

    assert [item.external_id for item in store.synced] == ["a", "noise"]
    assert store.complete == {"src"}
    assert (summary.listed, summary.kept, summary.inserted) == (3, 2, 2)
    assert summary.deactivated == 1
    assert (summary.enriched, summary.relevant) == (2, 1)
    assert enricher.details == {"a": "detail of a", "noise": "detail of noise"}
    assert store.commits == 3  # after sync, then once per saved enrichment
    assert summary.errors == []


async def test_failed_enrichment_is_reported_and_not_saved() -> None:
    store = FakeStore()

    summary = await run_ingestion(
        sources=[StaticSource("src", [make_listing("a"), make_listing("b")])],
        detail_readers={},
        enricher=FakeEnricher(fail_for={"b"}),
        store=store,
        observed_at=NOW,
    )

    assert summary.enriched == 1
    assert len(store.saved) == 1
    assert summary.errors == ["enrich https://example.org/b: model timeout"]


async def test_failed_detail_read_still_enriches_from_the_listing() -> None:
    enricher = FakeEnricher()

    summary = await run_ingestion(
        sources=[StaticSource("src", [make_listing("a")])],
        detail_readers={"src": FakeDetailReader(fail=True)},
        enricher=enricher,
        store=FakeStore(),
        observed_at=NOW,
    )

    assert summary.enriched == 1
    assert enricher.details == {"a": None}
    assert summary.errors == ["detail https://example.org/a: detail page down"]


async def test_failed_source_is_reported_and_its_registry_is_incomplete() -> None:
    store = FakeStore()

    summary = await run_ingestion(
        sources=[
            StaticSource("src", [make_listing("a")]),
            BrokenSource(source_id="other"),
        ],
        detail_readers={},
        enricher=FakeEnricher(),
        store=store,
        observed_at=NOW,
    )

    assert summary.failed_sources == ["other:broken: ValueError: markup changed"]
    assert store.complete == {"src"}
