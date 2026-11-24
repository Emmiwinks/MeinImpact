"""run_ingestion orchestration, against in-memory fakes of every port."""

import asyncio
import uuid
from collections.abc import Collection, Sequence
from dataclasses import replace
from datetime import date, datetime

from meinimpact.infrastructure.ai import usage
from meinimpact.infrastructure.ai.bundler import (
    Bundle,
    BundleItem,
    BundleOption,
    bundle_input_hash,
)
from meinimpact.infrastructure.ai.listing_enricher import (
    Enrichment,
    enrichment_input_hash,
)
from meinimpact.infrastructure.ai.usage import Price
from meinimpact.infrastructure.listings.model import Listing
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PendingEnrichment,
    SyncResult,
)
from meinimpact.infrastructure.pipeline.ingestion import RunBudget, run_ingestion
from tests.listing_fakes import NOW, BrokenSource, StaticSource, make_listing


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
            region="bund" if relevant else None,
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


class HangingEnricher(FakeEnricher):
    """Never finishes one listing, like a run whose machine is replaced."""

    async def enrich(self, listing: Listing, detail: str | None) -> Enrichment:
        if listing.external_id == "slow":
            await asyncio.Event().wait()
        return await super().enrich(listing, detail)


async def test_finished_enrichments_are_saved_while_others_still_run() -> None:
    store = FakeStore()
    source = StaticSource("src", [make_listing("slow"), make_listing("a")])

    run = asyncio.create_task(
        run_ingestion(
            sources=[source],
            detail_readers={},
            enricher=HangingEnricher(),
            store=store,
            observed_at=NOW,
        )
    )
    for _ in range(50):
        if store.saved:
            break
        await asyncio.sleep(0)
    run.cancel()

    assert [e.title for e in store.saved.values()] == ["Frage?"]
    assert store.commits == 2  # after sync, then the one finished enrichment


def _bundle_item(n: int, **changes: object) -> BundleItem:
    fields: dict[str, object] = {
        "id": uuid.UUID(int=n),
        "key": ("src", f"b{n}"),
        "kind": "petition",
        "source_org": "src",
        "organizer": None,
        "registry_title": f"R{n}",
        "title": f"T{n}",
        "summary": "S",
        "closes_on": None,
        "enrichment_input_hash": f"h{n}",
    }
    fields.update(changes)
    return BundleItem(**fields)  # type: ignore[arg-type]


class FakeBundleStore(FakeStore):
    def __init__(self, items: list[BundleItem]) -> None:
        super().__init__()
        self.items = items
        self.described: Sequence[tuple[Bundle, str]] = ()
        self.kept: Collection[uuid.UUID] = ()

    async def bundle_items(self, today: date) -> list[BundleItem]:
        return self.items

    async def save_bundles(
        self,
        today: date,
        *,
        described: Sequence[tuple[Bundle, str]],
        kept: Collection[uuid.UUID],
    ) -> None:
        self.described, self.kept = described, kept


class FakeBundler:
    def __init__(self, proposal: list[list[BundleItem]], *, fail: bool = False):
        self.proposal = proposal
        self.fail = fail
        self.offered: list[BundleItem] = []
        self.details: list[list[str | None]] = []

    async def propose_groups(
        self, items: Sequence[BundleItem]
    ) -> list[list[BundleItem]]:
        if self.fail:
            raise RuntimeError("model down")
        self.offered = list(items)
        return self.proposal

    async def describe(
        self, items: Sequence[BundleItem], details: Sequence[str | None]
    ) -> Bundle | None:
        self.details.append(list(details))
        return Bundle(
            header="h",
            title="t",
            summary="s",
            options={i.id: BundleOption("l", "d") for i in items},
        )


async def test_bundling_keeps_unchanged_bundles_and_describes_new_ones() -> None:
    old_a, old_b = _bundle_item(1), _bundle_item(2)
    kept_hash = bundle_input_hash([old_a, old_b])
    old_id = uuid.uuid4()
    existing = [
        replace(old_a, bundle_id=old_id, bundle_input_hash=kept_hash),
        replace(old_b, bundle_id=old_id, bundle_input_hash=kept_hash),
    ]
    new = [_bundle_item(3, key=("src", "a")), _bundle_item(4)]
    store = FakeBundleStore([*existing, *new, _bundle_item(5)])
    bundler = FakeBundler([new])

    summary = await run_ingestion(
        sources=[StaticSource("src", [make_listing("a")])],
        detail_readers={"src": FakeDetailReader()},
        enricher=FakeEnricher(),
        store=store,
        bundler=bundler,
        observed_at=NOW,
    )

    assert set(store.kept) == {old_a.id, old_b.id}
    # The kept bundle is never offered to the list pass again.
    assert {i.id.int for i in bundler.offered} == {3, 4, 5}
    [(bundle, input_hash)] = store.described
    assert set(bundle.options) == {new[0].id, new[1].id}
    assert input_hash == bundle_input_hash(new)
    # Full text where this run read the registry, none for the other.
    assert bundler.details == [["detail of a", None]]
    assert summary.bundles == 2
    assert summary.errors == []


async def test_a_failing_bundler_leaves_cards_as_they_were() -> None:
    store = FakeBundleStore([_bundle_item(1), _bundle_item(2)])

    summary = await run_ingestion(
        sources=[StaticSource("src", [make_listing("a")])],
        detail_readers={},
        enricher=FakeEnricher(),
        store=store,
        bundler=FakeBundler([], fail=True),
        observed_at=NOW,
    )

    assert summary.enriched == 1
    assert summary.errors == ["bundle: model down"]
    assert store.described == ()


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


class CostlyEnricher(FakeEnricher):
    """Reports one million prompt tokens per listing, as Mistral would."""

    async def enrich(self, listing: Listing, detail: str | None) -> Enrichment:
        usage.record(1_000_000, 0)
        return await super().enrich(listing, detail)


_ONE_EUR_PER_LISTING = Price(eur_per_m_input=1.0, eur_per_m_output=0.0)


async def test_budget_leaves_the_rest_pending_and_skips_bundling() -> None:
    store = FakeBundleStore([_bundle_item(1), _bundle_item(2)])
    bundler = FakeBundler([[_bundle_item(1), _bundle_item(2)]])

    summary = await run_ingestion(
        sources=[StaticSource("src", [make_listing(n) for n in ("a", "b", "c")])],
        detail_readers={},
        enricher=CostlyEnricher(),
        store=store,
        bundler=bundler,
        budget=RunBudget(price=_ONE_EUR_PER_LISTING, max_eur=1.5),
        observed_at=NOW,
        max_concurrency=1,
    )

    assert (summary.enriched, summary.deferred) == (2, 1)
    assert summary.budget_reached
    assert summary.cost_eur == 2.0
    assert len(store.saved) == 2
    assert bundler.offered == []  # bundling waits for the next run


async def test_each_source_gets_its_own_row_with_its_cost() -> None:
    summary = await run_ingestion(
        sources=[
            StaticSource("one", [make_listing("a"), make_listing("noise")]),
            StaticSource(
                "two",
                [
                    make_listing("x", source_id="b"),
                    make_listing("y", region=None, source_id="b"),
                ],
                source_id="b",
            ),
            BrokenSource(source_id="broken"),
        ],
        detail_readers={},
        enricher=CostlyEnricher(),
        store=FakeStore(),
        budget=RunBudget(price=_ONE_EUR_PER_LISTING, max_eur=100.0),
        observed_at=NOW,
    )

    rows = {row.source: row for row in summary.sources}
    one, two, broken = rows["one"], rows["two"], rows["broken:broken"]
    assert (one.fetched, one.kept, one.pending, one.enriched, one.relevant) == (
        2,
        2,
        2,
        2,
        1,
    )
    assert (one.calls, one.cost_eur) == (2, 2.0)
    assert (two.fetched, two.kept, two.enriched, two.cost_eur) == (2, 1, 1, 1.0)
    assert broken.error == "ValueError: markup changed"
    assert (summary.calls, summary.cost_eur) == (3, 3.0)


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
