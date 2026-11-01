"""Shared test doubles for listing sources and listings."""

from dataclasses import replace
from datetime import UTC, datetime

from meinimpact.infrastructure.listings.model import (
    ActionKind,
    Listing,
    ListingStatus,
    Region,
    Support,
)

NOW = datetime(2026, 11, 1, 12, 0, tzinfo=UTC)


def make_listing(
    external_id: str = "a",
    *,
    region: Region | None = Region.BUND,
    status: ListingStatus = ListingStatus.OPEN,
    source_id: str = "src",
    title: str | None = None,
    support_count: int | None = None,
) -> Listing:
    return Listing(
        source_id=source_id,
        external_id=external_id,
        url=f"https://example.org/{external_id}",
        title=title or f"Titel {external_id}",
        kind=ActionKind.PETITION,
        status=status,
        region=region,
        observed_at=NOW,
        support=Support(count=support_count),
    )


class StaticSource:
    def __init__(
        self, name: str, listings: list[Listing], *, source_id: str = "src"
    ) -> None:
        self._name = name
        self._listings = listings
        self._source_id = source_id

    @property
    def source_id(self) -> str:
        return self._source_id

    @property
    def name(self) -> str:
        return self._name

    async def fetch(self, *, observed_at: datetime) -> list[Listing]:
        return [replace(item, observed_at=observed_at) for item in self._listings]


class BrokenSource:
    def __init__(self, *, source_id: str = "broken") -> None:
        self._source_id = source_id

    @property
    def source_id(self) -> str:
        return self._source_id

    @property
    def name(self) -> str:
        return f"{self._source_id}:broken"

    async def fetch(self, *, observed_at: datetime) -> list[Listing]:
        raise ValueError("markup changed")
