"""WeAct (Campact): petitions featured on the WeAct homepage.

WeAct has no public full listing (its load-more endpoint sits under the
robots-disallowed /wp-json/), so this source reads the homepage's featured
petitions and then each petition page. Petition pages embed a JSON store
with signature count, goal, open/closed flags and the timestamps of the
latest signatures, a direct momentum signal. Signer names in that store are
discarded.
"""

import json
from collections.abc import Mapping
from datetime import datetime
from typing import Any
from urllib.parse import urljoin, urlsplit

from bs4 import BeautifulSoup

from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import (
    ActionKind,
    Listing,
    ListingStatus,
    Support,
)
from meinimpact.infrastructure.listings.parsing import (
    attr_of,
    clean_text,
    content_text,
)

SOURCE_ID = "weact"
BASE_URL = "https://weact.campact.de"
_PETITION_PATH = "/petitions/"


def parse_index(html: str) -> list[str]:
    """Canonical petition URLs linked from a page, deduplicated, in order."""
    soup = BeautifulSoup(html, "html.parser")
    urls: dict[str, None] = {}
    for element in soup.select("[href]"):
        href = attr_of(element, "href")
        if href is None:
            continue
        parts = urlsplit(urljoin(BASE_URL, href))
        if parts.netloc == urlsplit(BASE_URL).netloc and parts.path.startswith(
            _PETITION_PATH
        ):
            urls[f"{BASE_URL}{parts.path.rstrip('/')}"] = None
    return list(urls)


def parse_petition(html: str, *, url: str, observed_at: datetime) -> Listing | None:
    soup = BeautifulSoup(html, "html.parser")
    raw_store = attr_of(soup.select_one("[data-store-data]"), "data-store-data")
    title = attr_of(soup.select_one('meta[property="og:title"]'), "content")
    if raw_store is None or title is None:
        return None

    store: Mapping[str, Any] = json.loads(raw_store)
    petition = store.get("petition", {})
    progress = store.get("progress", {})
    closed = bool(petition.get("signatureFormHidden")) or bool(
        petition.get("successful")
    )
    summary = attr_of(soup.select_one('meta[property="description"]'), "content")
    return Listing(
        source_id=SOURCE_ID,
        external_id=str(petition.get("slug") or url.rsplit("/", 1)[-1]),
        url=url,
        title=clean_text(title),
        kind=ActionKind.PETITION,
        status=ListingStatus.CLOSED if closed else ListingStatus.OPEN,
        region="bund",
        observed_at=observed_at,
        organizer="WeAct",
        summary=clean_text(summary) if summary else None,
        support=Support(
            count=progress.get("currentSignaturesCount"),
            goal=progress.get("currentSignaturesGoal"),
            recent_activity=_recent_activity(store.get("recentActions", [])),
        ),
    )


def parse_petition_text(html: str) -> str | None:
    """Whom the petition addresses and its full text. The page's summary
    often only repeats the title, a slogan that can read either way
    ("sichere Zuflucht aus Sachsen-Anhalt"); the text says what it asks."""
    return content_text(html, ".petition-content")


def _recent_activity(actions: list[Mapping[str, Any]]) -> tuple[datetime, ...]:
    """Signature timestamps only; the names next to them are dropped here."""
    stamps: list[datetime] = []
    for action in actions:
        try:
            stamps.append(datetime.fromisoformat(str(action["createdAt"])))
        except KeyError, ValueError:
            continue
    return tuple(sorted(stamps, reverse=True))


class WeActSource:
    def __init__(self, http: PoliteHttpClient, *, max_petitions: int = 30) -> None:
        self._http = http
        self._max_petitions = max_petitions

    @property
    def source_id(self) -> str:
        return SOURCE_ID

    @property
    def name(self) -> str:
        return SOURCE_ID

    async def fetch(self, *, observed_at: datetime) -> list[Listing]:
        index = await self._http.get(f"{BASE_URL}/")
        listings: list[Listing] = []
        for url in parse_index(index.text)[: self._max_petitions]:
            page = await self._http.get(url)
            listing = parse_petition(page.text, url=url, observed_at=observed_at)
            if listing is not None:
                listings.append(listing)
        return listings


class WeActDetailReader:
    def __init__(self, http: PoliteHttpClient) -> None:
        self._http = http

    async def read(self, listing: Listing) -> str | None:
        return parse_petition_text((await self._http.get(listing.url)).text)
