"""Collector failure isolation, the composable steps, and source pagination."""

import json
from dataclasses import replace
from datetime import date
from pathlib import Path

import httpx

from meinimpact.infrastructure.listings import steps
from meinimpact.infrastructure.listings.catalog import (
    SOURCE_NAMES,
    default_detail_readers,
    default_sources,
)
from meinimpact.infrastructure.listings.collector import collect
from meinimpact.infrastructure.listings.http import CrawlPolicy, PoliteHttpClient
from meinimpact.infrastructure.listings.model import ListingStatus, Region
from meinimpact.infrastructure.listings.source import ListingSource
from meinimpact.infrastructure.listings.sources.eu_have_your_say import (
    EuHaveYourSaySource,
)
from meinimpact.infrastructure.listings.sources.openpetition import (
    OpenPetitionScope,
    OpenPetitionSource,
)
from meinimpact.infrastructure.listings.sources.sachsen_beteiligung import (
    SachsenBeteiligungSource,
)
from meinimpact.infrastructure.listings.sources.weact import WeActSource
from tests.listing_fakes import NOW, BrokenSource, StaticSource
from tests.listing_fakes import make_listing as _listing

FIXTURES = Path(__file__).parent / "fixtures" / "listings"


async def _no_sleep(_: float) -> None:
    return None


def _http(handler: httpx.MockTransport) -> PoliteHttpClient:
    return PoliteHttpClient(
        policy=CrawlPolicy(default_delay_s=0),
        client=httpx.AsyncClient(transport=handler),
        sleep=_no_sleep,
    )


# --- collector --------------------------------------------------------------


async def test_collect_isolates_a_failing_source() -> None:
    good = StaticSource("good", [_listing("a"), _listing("b")])

    report = await collect([good, BrokenSource()], observed_at=NOW)

    assert [item.external_id for item in report.listings] == ["a", "b"]
    assert [o.source for o in report.failed] == ["broken:broken"]
    assert report.failed[0].error == "ValueError: markup changed"


async def test_registry_with_one_failed_instance_is_not_complete() -> None:
    sources: list[ListingSource] = [
        StaticSource("op:bund", [_listing("a")], source_id="op"),
        BrokenSource(source_id="op"),
        StaticSource("eu", [_listing("b")], source_id="eu"),
    ]

    report = await collect(sources, observed_at=NOW)

    assert report.complete_source_ids == {"eu"}


async def test_collect_stamps_one_observation_time_for_the_run() -> None:
    report = await collect([StaticSource("s", [_listing()])], observed_at=NOW)

    assert report.observed_at == NOW
    assert report.listings[0].observed_at == NOW


# --- steps ------------------------------------------------------------------


def test_in_coverage_drops_listings_without_region() -> None:
    kept = steps.in_coverage([_listing("in"), _listing("out", region=None)])

    assert [item.external_id for item in kept] == ["in"]


def test_actionable_keeps_open_and_announced_only() -> None:
    listings = [_listing(status.value, status=status) for status in ListingStatus]

    kept = steps.actionable(listings)

    assert {item.status for item in kept} == {
        ListingStatus.OPEN,
        ListingStatus.ANNOUNCED,
    }


def test_not_expired_drops_past_end_dates_but_keeps_undated() -> None:
    today = date(2026, 11, 1)
    listings = [
        replace(_listing("past"), closes_on=date(2023, 6, 22)),
        replace(_listing("today"), closes_on=today),
        replace(_listing("future"), closes_on=date(2027, 1, 1)),
        _listing("undated"),
    ]

    kept = steps.not_expired(today)(listings)

    assert [item.external_id for item in kept] == ["today", "future", "undated"]


def test_dedupe_keeps_most_specific_region() -> None:
    listings = [
        _listing("p", region=Region.SACHSEN),
        _listing("p", region=Region.DRESDEN),
        _listing("p", region=Region.BUND),
        _listing("p", region=Region.BUND, source_id="other"),
    ]

    kept = steps.dedupe(listings)

    assert sorted((i.source_id, str(i.region)) for i in kept) == [
        ("other", "bund"),
        ("src", "dresden"),
    ]


def test_apply_runs_steps_in_order() -> None:
    listings = [
        _listing("a", region=None),
        _listing("b", status=ListingStatus.CLOSED),
        _listing("c"),
        _listing("c", region=Region.DRESDEN),
    ]

    kept = steps.apply(listings, (steps.in_coverage, steps.actionable, steps.dedupe))

    assert [(i.external_id, i.region) for i in kept] == [("c", Region.DRESDEN)]


# --- sources over a mocked transport ----------------------------------------


async def test_openpetition_pages_until_no_new_petitions() -> None:
    page = (FIXTURES / "openpetition_listing.html").read_text(encoding="utf-8")
    pages_requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        pages_requested.append(request.url.params["seite"])
        return httpx.Response(200, text=page)  # same cards on every page

    source = OpenPetitionSource(
        _http(httpx.MockTransport(handler)),
        OpenPetitionScope(Region.DRESDEN, "/region/petition/Dresden"),
        max_pages=5,
    )

    listings = await source.fetch(observed_at=NOW)

    assert len(listings) == 3
    assert pages_requested == ["1", "2"]
    assert source.name == "openpetition:dresden"


async def test_sachsen_follows_ajax_pagination_with_view_state() -> None:
    first = (FIXTURES / "sachsen_listing.html").read_text(encoding="utf-8")
    second = (FIXTURES / "sachsen_page2.xml").read_text(encoding="utf-8")
    posts: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        if request.method == "GET":
            return httpx.Response(200, text=first)
        posts.append(request)
        body = second if len(posts) == 1 else "<partial-response/>"
        return httpx.Response(200, text=body)

    source = SachsenBeteiligungSource(_http(httpx.MockTransport(handler)))

    listings = await source.fetch(observed_at=NOW)

    assert len(listings) == 5
    assert len(posts) == 2  # second POST returns nothing, paging stops
    form = posts[0].content.decode()
    assert "tabForm%3AbeteiligungList%3AdataList_first=10" in form
    assert "tabForm%3AbeteiligungList%3AdataList_rows=10" in form
    assert "jakarta.faces.ViewState=" in form
    assert posts[0].headers["Faces-Request"] == "partial/ajax"


async def test_sachsen_rejected_pagination_fails_the_source_loudly() -> None:
    first = (FIXTURES / "sachsen_listing.html").read_text(encoding="utf-8")
    redirect = (
        "<partial-response><changes><redirect url='/portal/sachsen/500'/>"
        "</changes></partial-response>"
    )

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        return httpx.Response(200, text=first if request.method == "GET" else redirect)

    source = SachsenBeteiligungSource(_http(httpx.MockTransport(handler)))

    report = await collect([source], observed_at=NOW)

    assert report.failed[0].error is not None
    assert report.failed[0].error.startswith("PaginationRejectedError")


async def test_eu_pages_until_the_api_reports_the_last_page() -> None:
    payload = json.loads((FIXTURES / "eu_have_your_say.json").read_text("utf-8"))
    pages: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        pages.append(request.url.params["page"])
        payload["initiativeResultDtoPage"]["last"] = len(pages) == 2
        return httpx.Response(200, json=payload)

    source = EuHaveYourSaySource(_http(httpx.MockTransport(handler)), max_pages=5)

    listings = await source.fetch(observed_at=NOW)

    assert pages == ["0", "1"]
    assert len(listings) == 6


async def test_weact_reads_index_then_each_petition_page() -> None:
    index = (FIXTURES / "weact_index.html").read_text(encoding="utf-8")
    petition = (FIXTURES / "weact_petition.html").read_text(encoding="utf-8")
    requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/robots.txt":
            return httpx.Response(404)
        requested.append(request.url.path)
        if request.url.path == "/":
            return httpx.Response(200, text=index)
        if request.url.path.endswith("informationsfreiheit"):
            return httpx.Response(200, text="<html>no store</html>")
        return httpx.Response(200, text=petition)

    source = WeActSource(_http(httpx.MockTransport(handler)), max_petitions=3)

    listings = await source.fetch(observed_at=NOW)

    assert requested[0] == "/"
    assert len(requested) == 4
    assert len(listings) == 2  # the page without a store is skipped


async def test_default_sources_are_uniquely_named() -> None:
    async with PoliteHttpClient() as http:
        names = [source.name for source in default_sources(http)]

    assert len(names) == len(set(names))
    assert "openpetition:dresden" in names


async def test_every_configured_registry_has_a_display_name() -> None:
    async with PoliteHttpClient() as http:
        source_ids = {s.source_id for s in default_sources(http)}
        reader_ids = set(default_detail_readers(http))

    assert source_ids == set(SOURCE_NAMES)
    assert reader_ids <= source_ids


def test_default_steps_apply_the_full_policy() -> None:
    today = date(2026, 11, 1)
    listings = [
        _listing("out", region=None),
        _listing("closed", status=ListingStatus.CLOSED),
        replace(_listing("expired"), closes_on=date(2026, 10, 1)),
        _listing("dup", region=Region.SACHSEN),
        _listing("dup", region=Region.DRESDEN),
    ]

    kept = steps.apply(listings, steps.default_steps(today))

    assert [(i.external_id, i.region) for i in kept] == [("dup", Region.DRESDEN)]
