"""Composable steps over collected listings.

Each step is a pure function `Sequence[Listing] -> list[Listing]`, so a run
is just the steps applied in order. Sources stay dumb (report what the
registry says); every policy decision lives here, where it can be tested
and reordered on its own.
"""

from collections.abc import Callable, Sequence
from datetime import date

from meinimpact import places
from meinimpact.infrastructure.listings.model import Listing, ListingStatus

Step = Callable[[Sequence[Listing]], list[Listing]]


def in_coverage(listings: Sequence[Listing]) -> list[Listing]:
    """Drops listings outside the app's regions."""
    return [listing for listing in listings if listing.region is not None]


def actionable(listings: Sequence[Listing]) -> list[Listing]:
    """Keeps listings someone can act on now or soon."""
    return [
        listing
        for listing in listings
        if listing.status in (ListingStatus.OPEN, ListingStatus.ANNOUNCED)
    ]


def not_expired(today: date) -> Step:
    """Drops listings whose end date has passed.

    Registries keep stale entries flagged as running (seen live: an
    openPetition petition "open" since 2023, a portal survey "Aktiv" since
    2020), so the status label alone is not trusted. Listings without an end
    date pass.
    """

    def step(listings: Sequence[Listing]) -> list[Listing]:
        return [
            listing
            for listing in listings
            if listing.closes_on is None or listing.closes_on >= today
        ]

    return step


def dedupe(listings: Sequence[Listing]) -> list[Listing]:
    """One listing per registry entry, keeping its most specific region
    (openPetition lists Dresden petitions on the Sachsen page too)."""
    best: dict[tuple[str, str], Listing] = {}
    for listing in listings:
        current = best.get(listing.key)
        if current is None or places.depth_of(listing.region) > places.depth_of(
            current.region
        ):
            best[listing.key] = listing
    return list(best.values())


def default_steps(today: date) -> tuple[Step, ...]:
    """The policy every ingestion run applies, in order."""
    return (in_coverage, actionable, not_expired(today), dedupe)


def apply(listings: Sequence[Listing], steps: Sequence[Step]) -> list[Listing]:
    result = list(listings)
    for step in steps:
        result = step(result)
    return result
