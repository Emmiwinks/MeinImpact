"""EU "Have your say": initiatives currently open for public feedback.

Uses the JSON API behind the portal's own search page. Titles come in all
EU languages; the German one is used, falling back to the English short
title.
"""

from collections.abc import Mapping
from datetime import date, datetime
from typing import Any

from bs4 import BeautifulSoup

from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import (
    ActionKind,
    Listing,
    ListingStatus,
    Region,
)
from meinimpact.infrastructure.listings.parsing import clean_text, text_of

SOURCE_ID = "eu-have-your-say"
_BASE_URL = "https://ec.europa.eu/info/law/better-regulation"
API_URL = f"{_BASE_URL}/brpapi/searchInitiatives"
DETAIL_URL = _BASE_URL + "/brpapi/groupInitiatives/{id}"
ITEM_URL = _BASE_URL + "/have-your-say/initiatives/{id}_de"
_DATE_FORMAT = "%Y/%m/%d %H:%M:%S"


def parse_search_page(
    payload: Mapping[str, Any], *, observed_at: datetime
) -> tuple[list[Listing], bool]:
    """Returns the page's listings and whether it was the last page."""
    page = payload["initiativeResultDtoPage"]
    listings = [
        _parse_initiative(item, observed_at=observed_at) for item in page["content"]
    ]
    return listings, bool(page["last"])


def _parse_initiative(item: Mapping[str, Any], *, observed_at: datetime) -> Listing:
    initiative_id = str(int(item["id"]))
    current: Mapping[str, Any] = next(
        (s for s in item.get("currentStatuses", []) if s.get("isCurrent")), {}
    )
    return Listing(
        source_id=SOURCE_ID,
        external_id=initiative_id,
        url=ITEM_URL.format(id=initiative_id),
        title=_german_title(item),
        kind=ActionKind.CONSULTATION,
        status=_status(current.get("receivingFeedbackStatus")),
        region=Region.EU,
        observed_at=observed_at,
        organizer="Europäische Kommission",
        opens_on=_date(current.get("feedbackStartDate")),
        closes_on=_date(current.get("feedbackEndDate")),
        source_labels=tuple(
            label for t in item.get("topics", []) if (label := t.get("label"))
        ),
    )


def _german_title(item: Mapping[str, Any]) -> str:
    for translation in item.get("initiativeTranslations", []):
        if (
            translation.get("language") == "DE"
            and translation.get("field") == "SHORT_TITLE"
        ):
            return str(translation["value"]).strip()
    return str(item["shortTitle"]).strip()


def _status(value: str | None) -> ListingStatus:
    return {
        "OPEN": ListingStatus.OPEN,
        "CLOSED": ListingStatus.CLOSED,
    }.get(value or "", ListingStatus.UNKNOWN)


def _date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return datetime.strptime(value, _DATE_FORMAT).date()
    except ValueError:
        return None


def parse_initiative_summary(payload: Mapping[str, Any]) -> str | None:
    """German summary of one initiative (HTML in the API), else English."""
    for translation in payload.get("initiativeTranslations", []):
        if (
            translation.get("language") == "DE"
            and translation.get("field") == "SUMMARY"
        ):
            return text_of(BeautifulSoup(str(translation["value"]), "html.parser"))
    return clean_text(str(payload.get("dossierSummary") or "")) or None


class EuHaveYourSaySource:
    def __init__(
        self, http: PoliteHttpClient, *, page_size: int = 50, max_pages: int = 5
    ) -> None:
        self._http = http
        self._page_size = page_size
        self._max_pages = max_pages

    @property
    def source_id(self) -> str:
        return SOURCE_ID

    @property
    def name(self) -> str:
        return SOURCE_ID

    async def fetch(self, *, observed_at: datetime) -> list[Listing]:
        listings: list[Listing] = []
        for page in range(self._max_pages):
            response = await self._http.get(
                API_URL,
                params={
                    "feedbackStatus": "OPEN",
                    "language": "DE",
                    "page": page,
                    "size": self._page_size,
                },
            )
            batch, is_last = parse_search_page(response.json(), observed_at=observed_at)
            listings.extend(batch)
            if is_last:
                break
        return listings


class EuHaveYourSayDetailReader:
    def __init__(self, http: PoliteHttpClient) -> None:
        self._http = http

    async def read(self, listing: Listing) -> str | None:
        response = await self._http.get(DETAIL_URL.format(id=listing.external_id))
        return parse_initiative_summary(response.json())
