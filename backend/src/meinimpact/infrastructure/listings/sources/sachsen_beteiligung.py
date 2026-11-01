"""Beteiligungsportal Sachsen: all current participation procedures in Saxony.

One portal for the state government and most Saxon municipalities, Dresden
included: consultations, surveys, Bauleitplanung displays, events, notices.
The list is a PrimeFaces DataList. The first page is plain HTML; further
pages come from the same AJAX call the paginator makes (session cookie +
ViewState). Which authority runs a procedure decides its coverage region.
"""

import re
from collections.abc import Callable
from datetime import datetime

from bs4 import BeautifulSoup, Tag

from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import (
    ActionKind,
    Listing,
    ListingStatus,
    Region,
    Support,
)
from meinimpact.infrastructure.listings.parsing import (
    attr_of,
    parse_german_dates,
    parse_german_int,
    text_of,
)

SOURCE_ID = "beteiligung-sachsen"
BASE_URL = "https://buergerbeteiligung.sachsen.de"
_DATA_LIST = "tabForm:beteiligungList:dataList"
_PAGE_SIZE = 10  # the portal's own page size; it rejects any other
_TOTAL = re.compile(r"\d+\s*-\s*\d+\s*von\s*(\d+)")
_PARTIAL_UPDATE = re.compile(
    r'<update id="' + re.escape(_DATA_LIST) + r'"><!\[CDATA\[(.*?)\]\]></update>',
    re.DOTALL,
)
_AJAX_HEADERS = {
    "Faces-Request": "partial/ajax",
    "X-Requested-With": "XMLHttpRequest",
}

RegionResolver = Callable[[str], Region | None]

_MUNICIPAL_PREFIXES = (
    "Stadt ",
    "Gemeinde ",
    "Große Kreisstadt",
    "Landkreis",
    "Landratsamt",
    "Verwaltungsverband",
    "Verwaltungsgemeinschaft",
    "Zweckverband",
)
_STATE_MARKERS = (
    "Staatsministerium",
    "Staatskanzlei",
    "Landesdirektion",
    "Landesamt",
    "Sächsische Staats",
    "Sächsisches",
    "Freistaat Sachsen",
)


def region_for_authority(authority: str) -> Region | None:
    """Maps the portal's authority ("Mandant") onto the app's coverage."""
    if "Dresden" in authority:
        return Region.DRESDEN
    if authority.startswith(_MUNICIPAL_PREFIXES):
        return None
    if any(marker in authority for marker in _STATE_MARKERS):
        return Region.SACHSEN
    return None


def parse_teasers(
    html: str,
    *,
    observed_at: datetime,
    resolve_region: RegionResolver = region_for_authority,
) -> list[Listing]:
    soup = BeautifulSoup(html, "html.parser")
    listings = (
        _parse_teaser(teaser, observed_at=observed_at, resolve_region=resolve_region)
        for teaser in soup.select("div.nbp-teaser")
    )
    return [listing for listing in listings if listing is not None]


def parse_total(html: str) -> int | None:
    match = _TOTAL.search(html)
    return int(match.group(1)) if match else None


def parse_view_state(html: str) -> str | None:
    soup = BeautifulSoup(html, "html.parser")
    return attr_of(soup.select_one('input[name="jakarta.faces.ViewState"]'), "value")


class PaginationRejectedError(Exception):
    """The portal answered a page request with a redirect to its error page."""


def parse_partial_response(xml: str) -> str:
    """The data list's HTML from a JSF partial response ("" if absent).

    Raises PaginationRejectedError when the portal redirects instead (it does
    so e.g. for an unsupported page size), so a broken paginator shows up as
    a failed source rather than as a silently short list.
    """
    if "<redirect" in xml:
        raise PaginationRejectedError(xml[:300])
    match = _PARTIAL_UPDATE.search(xml)
    return match.group(1) if match else ""


def _parse_teaser(
    teaser: Tag, *, observed_at: datetime, resolve_region: RegionResolver
) -> Listing | None:
    link = teaser.select_one("h3.nbp-teaser-title a[href]")
    href = attr_of(link, "href")
    title = text_of(link)
    if href is None or title is None:
        return None

    procedure_type = text_of(teaser.select_one(".nbp-teaser-taglist--beteiligungstyp"))
    step = text_of(teaser.select_one(".nbp-teaser-taglist--verfahrensschritt"))
    topic = text_of(teaser.select_one(".nbp-teaser-taglist--thema"))
    authority = text_of(teaser.select_one(".nbp-teaser-taglist--mandant"))
    status = text_of(teaser.select_one(".nbp-statistik--status span:last-of-type"))
    dates = parse_german_dates(text_of(teaser.select_one(".nbp-statistik--laufzeit")))
    participants = teaser.select_one(
        ".nbp-statistik--umfrageteilnehmer, .nbp-statistik--stellungnahmen"
    )

    return Listing(
        source_id=SOURCE_ID,
        external_id=href.rstrip("/").rsplit("/", 1)[-1],
        url=BASE_URL + href,
        title=title,
        kind=_kind(procedure_type, step, status),
        status=_status(status),
        region=resolve_region(authority) if authority else None,
        observed_at=observed_at,
        locality=authority,
        organizer=authority,
        summary=text_of(teaser.select_one(".nbp-teaser-text")),
        opens_on=dates[0] if dates else None,
        closes_on=dates[-1] if dates else None,
        support=Support(count=parse_german_int(text_of(participants))),
        source_labels=tuple(
            label for label in (procedure_type, step, topic) if label is not None
        ),
    )


def _kind(
    procedure_type: str | None, step: str | None, status: str | None
) -> ActionKind:
    labels = " ".join(v for v in (procedure_type, step, status) if v).lower()
    if "beschluss" in labels or "bekanntmachung" in labels:
        return ActionKind.NOTICE
    if any(word in labels for word in ("auslegung", "bebauungsplan", "nutzungsplan")):
        return ActionKind.PUBLIC_DISPLAY
    if "umfrage" in labels:
        return ActionKind.SURVEY
    if "veranstaltung" in labels:
        return ActionKind.EVENT
    if any(word in labels for word in ("dialog", "verfahren", "konsultation")):
        return ActionKind.CONSULTATION
    return ActionKind.OTHER


def _status(value: str | None) -> ListingStatus:
    return {
        "aktiv": ListingStatus.OPEN,
        "ankündigung": ListingStatus.ANNOUNCED,
        "beendet": ListingStatus.CLOSED,
        "beschluss": ListingStatus.CLOSED,
    }.get((value or "").lower(), ListingStatus.UNKNOWN)


def _pagination_form(view_state: str, first: int, rows: int) -> dict[str, str]:
    """The form the PrimeFaces paginator posts for rows [first, first+rows)."""
    return {
        "jakarta.faces.partial.ajax": "true",
        "jakarta.faces.source": _DATA_LIST,
        "jakarta.faces.partial.execute": _DATA_LIST,
        "jakarta.faces.partial.render": _DATA_LIST,
        f"{_DATA_LIST}_pagination": "true",
        f"{_DATA_LIST}_first": str(first),
        f"{_DATA_LIST}_rows": str(rows),
        f"{_DATA_LIST}_encodeFeature": "true",
        "tabForm": "tabForm",
        "jakarta.faces.ViewState": view_state,
    }


class SachsenBeteiligungSource:
    """Reads the portal's full list of current procedures.

    `portal` selects the portal instance ("sachsen" = everything, or an
    authority's own portal like "dresden"). Pages are fixed at the portal's
    own size of 10; it rejects any other.
    """

    def __init__(
        self,
        http: PoliteHttpClient,
        *,
        portal: str = "sachsen",
        max_items: int = 1500,
        resolve_region: RegionResolver = region_for_authority,
    ) -> None:
        self._http = http
        self._url = f"{BASE_URL}/portal/{portal}/beteiligung/themen"
        self._portal = portal
        self._max_items = max_items
        self._resolve_region = resolve_region

    @property
    def source_id(self) -> str:
        return SOURCE_ID

    @property
    def name(self) -> str:
        return f"{SOURCE_ID}:{self._portal}"

    async def fetch(self, *, observed_at: datetime) -> list[Listing]:
        first_page = (await self._http.get(self._url)).text
        listings = self._parse(first_page, observed_at)
        view_state = parse_view_state(first_page)
        total = min(parse_total(first_page) or 0, self._max_items)
        if view_state is None:
            return listings

        for first in range(_PAGE_SIZE, total, _PAGE_SIZE):
            response = await self._http.post_form(
                self._url,
                data=_pagination_form(view_state, first, _PAGE_SIZE),
                headers=_AJAX_HEADERS,
            )
            batch = self._parse(parse_partial_response(response.text), observed_at)
            if not batch:
                break
            listings.extend(batch)
        return listings

    def _parse(self, html: str, observed_at: datetime) -> list[Listing]:
        return parse_teasers(
            html, observed_at=observed_at, resolve_region=self._resolve_region
        )
