"""openPetition: running petitions per region, read from the public listings.

The region pages (`/region/petition/<Name>`) list running petitions first,
then ones past collection, paginated with `?seite=N`. Each card carries
everything needed: title, slug, category, region label, signatures (plus
"(+N)" collected via partners), and, for running petitions, the exact end
date in the days-left element's `title`.
"""

from dataclasses import dataclass
from datetime import date, datetime

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
    content_text,
    parse_german_int,
    parse_german_long_date,
    text_of,
)

SOURCE_ID = "openpetition"
BASE_URL = "https://www.openpetition.de"
_PETITION_PATH = "/petition/online/"


@dataclass(frozen=True, slots=True)
class OpenPetitionScope:
    """One openPetition region page mapped onto an app coverage region."""

    region: Region
    path: str


def parse_listing_page(
    html: str, *, region: Region, observed_at: datetime
) -> list[Listing]:
    soup = BeautifulSoup(html, "html.parser")
    listings = (
        _parse_card(card, region=region, observed_at=observed_at)
        for card in soup.select("div.module-petition-summary")
    )
    return [listing for listing in listings if listing is not None]


def _parse_card(card: Tag, *, region: Region, observed_at: datetime) -> Listing | None:
    link = card.select_one(f'h3 a[href^="{_PETITION_PATH}"]')
    href = attr_of(link, "href")
    title = text_of(link)
    if href is None or title is None:
        return None

    days_left = card.select_one(".petition-days-left")
    closes_on = parse_german_long_date(attr_of(days_left, "title"))
    category = text_of(card.select_one(".box-content-top > a"))
    return Listing(
        source_id=SOURCE_ID,
        external_id=href.removeprefix(_PETITION_PATH),
        url=BASE_URL + href,
        title=title,
        kind=ActionKind.PETITION,
        status=_status(closes_on, phase=text_of(days_left)),
        region=region,
        observed_at=observed_at,
        locality=text_of(card.select_one(".box-header-top-text")),
        closes_on=closes_on,
        support=Support(
            count=parse_german_int(text_of(card.select_one(".petition-signer-count"))),
            partner_count=parse_german_int(
                text_of(card.select_one('[title="über Partner"]'))
            ),
        ),
        source_labels=(category,) if category else (),
    )


def _status(closes_on: date | None, *, phase: str | None) -> ListingStatus:
    """Running petitions carry their end date in the countdown's `title`.

    Region pages also list petitions past collection; their countdown
    element then counts the other way ("346 Tage seit Sammlung", "347 Tage
    im Dialog") and has no end date.
    """
    if closes_on is not None:
        return ListingStatus.OPEN
    return ListingStatus.CLOSED if phase else ListingStatus.UNKNOWN


class OpenPetitionSource:
    """Reads the first `max_pages` pages of one openPetition region listing.

    Pages are ordered by signature count, so the page cap keeps the largest
    running petitions of the region.
    """

    def __init__(
        self, http: PoliteHttpClient, scope: OpenPetitionScope, *, max_pages: int = 3
    ) -> None:
        self._http = http
        self._scope = scope
        self._max_pages = max_pages

    @property
    def source_id(self) -> str:
        return SOURCE_ID

    @property
    def name(self) -> str:
        return f"{SOURCE_ID}:{self._scope.region}"

    async def fetch(self, *, observed_at: datetime) -> list[Listing]:
        by_id: dict[str, Listing] = {}
        for page in range(1, self._max_pages + 1):
            response = await self._http.get(
                BASE_URL + self._scope.path, params={"seite": page}
            )
            batch = parse_listing_page(
                response.text, region=self._scope.region, observed_at=observed_at
            )
            new = [item for item in batch if item.external_id not in by_id]
            if not new:
                break
            by_id.update((item.external_id, item) for item in new)
        return list(by_id.values())


def parse_petition_text(html: str) -> str | None:
    """The petition's own text from its detail page."""
    return content_text(html, "#petition-main")


class OpenPetitionDetailReader:
    def __init__(self, http: PoliteHttpClient) -> None:
        self._http = http

    async def read(self, listing: Listing) -> str | None:
        return parse_petition_text((await self._http.get(listing.url)).text)
