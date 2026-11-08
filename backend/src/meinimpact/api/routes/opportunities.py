"""Civic opportunity routes: the feed's single data source.

One opportunity is one registry entry (a petition, a consultation, a
Bauleitplan display...), so the pool response already carries everything
the feed card and its detail view need. No separate detail endpoint; only
council decisions have one more: the recipients of a letter.
"""

from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import (
    get_council_repository,
    get_opportunity_repository,
    require_principal,
)
from meinimpact.domain import repositories
from meinimpact.infrastructure.council.offices import FRAKTION_OFFICES
from meinimpact.infrastructure.council.postgres_council_repository import (
    PostgresCouncilRepository,
)
from meinimpact.infrastructure.listings.model import ActionKind
from meinimpact.services.recipients import resolve_recipients

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


@router.get("/{opportunity_id}/recipients")
async def get_letter_recipients(
    opportunity_id: UUID,
    opportunity_repository: repositories.OpportunityRepository = Depends(
        get_opportunity_repository
    ),
    council_repository: PostgresCouncilRepository = Depends(get_council_repository),
) -> schemas.RecipientsResponse:
    """Who a letter about a council decision goes to (`services/recipients`)."""
    opportunity = await opportunity_repository.get(opportunity_id)
    if opportunity is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Opportunity not found."
        )
    if opportunity.kind != ActionKind.DECISION.value:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Recipients exist for council decisions only.",
        )
    members = await council_repository.members_of(opportunity.recipient_bodies)
    recipients = resolve_recipients(members, FRAKTION_OFFICES)
    return schemas.RecipientsResponse(
        bodies=recipients.bodies,
        members=[
            schemas.RecipientMemberResponse(name=m.name, fraktion=m.fraktion)
            for m in recipients.members
        ],
        offices=[
            schemas.RecipientOfficeResponse(fraktion=o.fraktion, email=o.email)
            for o in recipients.offices
        ],
    )
