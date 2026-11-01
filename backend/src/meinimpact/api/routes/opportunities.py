"""Civic opportunity routes: the feed's single data source.

One opportunity is one registry entry (a petition, a consultation, a
Bauleitplan display...), so the pool response already carries everything
the feed card and its detail view need. No separate detail endpoint.
"""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_opportunity_repository, require_principal
from meinimpact.domain import repositories

router = APIRouter(
    prefix="/v1/opportunities",
    tags=["opportunities"],
    dependencies=[Depends(require_principal)],
)


@router.get("/pool")
async def get_opportunity_pool(
    opportunity_repository: repositories.OpportunityRepository = Depends(
        get_opportunity_repository
    ),
) -> schemas.OpportunityPoolResponse:
    """Returns every relevant opportunity that is still open today."""
    now = datetime.now(UTC)
    opportunities = await opportunity_repository.list_open(now.date())
    return schemas.OpportunityPoolResponse(
        opportunities=[
            schemas.OpportunityResponse.from_domain(o) for o in opportunities
        ],
        generated_at=now,
    )
