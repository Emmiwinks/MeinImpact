"""Civic opportunity API routes — the new Tavily-sourced pool, replacing
`civic_actions`/`CivicAction`. See `domain/entities.py`'s `Opportunity`
docstring: no topic/option grouping, one row is already one deduplicated,
standalone thing, so there's no separate detail endpoint — the pool
response already carries everything the feed card and its popup need.
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
    """Returns the current ingestion run's opportunities — see
    `OpportunityRepository.list_current_run` for why this is never an
    accumulating pool."""
    opportunities = await opportunity_repository.list_current_run()
    return schemas.OpportunityPoolResponse(
        opportunities=[
            schemas.OpportunityResponse.from_domain(o) for o in opportunities
        ],
        generated_at=datetime.now(UTC),
    )
