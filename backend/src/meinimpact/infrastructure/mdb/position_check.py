"""Composes the 3 MdB-position sources into one check.

Per specs/data/sources-federal.md "Source 6: MdB Public Statements". This
module has no source-specific logic of its own — it only fans out to the
`PositionCheckAdapter` implementations in `infrastructure/sources/` and
aggregates their results.

Used by two call sites: the ingestion pipeline's state-B rule (via
`BuildRuleContextStep`, component 5) and the existing MdB-statement tracking
refresh (`specs/features/tracking.md` Stage 6) — same function, zero
duplication between them.
"""

import asyncio
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime

from meinimpact.infrastructure.sources.protocol import (
    MdbTarget,
    PositionCheckAdapter,
    PositionCheckResult,
)


@dataclass(frozen=True)
class MdbPositionCheckResult:
    """Aggregated outcome across all 3 position-check sources."""

    found: bool
    matches: tuple[PositionCheckResult, ...]

    @property
    def matched_source(self) -> PositionCheckResult | None:
        """The first source that found a statement, or None if all 3 didn't."""
        return next((m for m in self.matches if m.found), None)


async def check_mdb_position(
    mdb: MdbTarget,
    descriptors: list[str],
    since: datetime,
    adapters: Sequence[PositionCheckAdapter],
) -> MdbPositionCheckResult:
    """Runs all given position-check adapters in parallel and aggregates.

    `found=True` if ANY adapter finds a statement; `found=False` only if
    ALL of them return no match — per specs/data/ingestion-pipeline.md
    "State B triggers".
    """
    results = await asyncio.gather(
        *[adapter.check_position(mdb, descriptors, since) for adapter in adapters]
    )
    return MdbPositionCheckResult(
        found=any(r.found for r in results), matches=tuple(results)
    )
