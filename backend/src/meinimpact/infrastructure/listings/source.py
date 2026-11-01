"""The protocols listing sources implement."""

from datetime import datetime
from typing import Protocol

from meinimpact.infrastructure.listings.model import Listing


class ListingSource(Protocol):
    """A registry adapter: fetches the registry and returns its listings.

    `source_id` is the registry (the `Listing.source_id` it produces);
    `name` identifies one configured instance in reports, since the same
    registry can be configured several times (e.g. openPetition per region).
    Implementations raise on failure; isolating failures is the collector's
    job, not the source's.
    """

    @property
    def source_id(self) -> str: ...

    @property
    def name(self) -> str: ...

    async def fetch(self, *, observed_at: datetime) -> list[Listing]: ...


class DetailReader(Protocol):
    """Reads the full text behind a listing, for registries whose list view
    carries little more than a title. Returns None when there is nothing
    usable; raises on transport errors."""

    async def read(self, listing: Listing) -> str | None: ...
