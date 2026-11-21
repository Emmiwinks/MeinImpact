"""Repository interfaces for domain services."""

import uuid
from collections.abc import Sequence
from datetime import date
from typing import Protocol

from meinimpact.domain.entities import Opportunity


class OpportunityRepository(Protocol):
    """API-side persistence boundary for civic opportunities."""

    async def list_open(self, today: date) -> Sequence[Opportunity]:
        """Relevant opportunities still listed by their registry and not
        closed before `today`."""

    async def get(self, opportunity_id: uuid.UUID) -> Opportunity | None:
        """One opportunity by id, whether or not it is still served."""

    async def mark_tracked(self, opportunity_id: uuid.UUID, today: date) -> bool:
        """Marks that someone did this opportunity, keeping the first day.
        False if the id is unknown."""

    async def commit(self) -> None:
        """Commits pending writes."""
