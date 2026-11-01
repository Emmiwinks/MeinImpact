"""Runs listing sources concurrently and isolates their failures.

A registry changing its markup must cost us that registry for one run, not
the whole run. Each source's outcome (listings or error, plus timing) is
reported separately.
"""

import asyncio
import logging
import time
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import UTC, datetime

from meinimpact.infrastructure.listings.model import Listing
from meinimpact.infrastructure.listings.source import ListingSource

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class SourceOutcome:
    source_id: str
    source: str
    listings: tuple[Listing, ...]
    duration_s: float
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


@dataclass(frozen=True, slots=True)
class CollectionReport:
    observed_at: datetime
    outcomes: tuple[SourceOutcome, ...]

    @property
    def listings(self) -> list[Listing]:
        return [listing for o in self.outcomes for listing in o.listings]

    @property
    def failed(self) -> list[SourceOutcome]:
        return [o for o in self.outcomes if not o.ok]

    @property
    def complete_source_ids(self) -> frozenset[str]:
        """Registries whose every configured instance succeeded this run.

        Only for these is "not listed anymore" a fact (closed, removed). A
        registry with one failed instance is incomplete: its missing
        listings may just be unread.
        """
        failed = {o.source_id for o in self.failed}
        return frozenset(
            o.source_id for o in self.outcomes if o.source_id not in failed
        )


async def collect(
    sources: Sequence[ListingSource], *, observed_at: datetime | None = None
) -> CollectionReport:
    """Fetches all sources concurrently; one observation time for the run."""
    observed_at = observed_at or datetime.now(UTC)
    outcomes = await asyncio.gather(*(_run(s, observed_at) for s in sources))
    return CollectionReport(observed_at=observed_at, outcomes=tuple(outcomes))


async def _run(source: ListingSource, observed_at: datetime) -> SourceOutcome:
    started = time.perf_counter()
    try:
        listings = await source.fetch(observed_at=observed_at)
    except Exception as exc:  # isolation boundary: one source, not the run
        logger.exception("Listing source %s failed", source.name)
        return SourceOutcome(
            source_id=source.source_id,
            source=source.name,
            listings=(),
            duration_s=time.perf_counter() - started,
            error=f"{type(exc).__name__}: {exc}",
        )
    return SourceOutcome(
        source_id=source.source_id,
        source=source.name,
        listings=tuple(listings),
        duration_s=time.perf_counter() - started,
    )
