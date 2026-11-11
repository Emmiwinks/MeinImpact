"""Civic opportunity routes: the feed's single data source.

One opportunity is one registry entry (a petition, a consultation, a
Bauleitplan display...), so the pool response already carries everything
the feed card and its detail view need. No separate detail endpoint; only
council decisions have one more: the recipients of a letter. `tracked`
takes the app's anonymous mark that someone did an opportunity; `news`
serves what Mein Impact found on all tracked ones.
"""

from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import (
    get_council_repository,
    get_impact_news_repository,
    get_opportunity_repository,
    require_principal,
)
from meinimpact.domain import repositories
from meinimpact.infrastructure.council.offices import FRAKTION_OFFICES
from meinimpact.infrastructure.council.postgres_council_repository import (
    PostgresCouncilRepository,
)
from meinimpact.infrastructure.impact.postgres_news_repository import (
    PostgresImpactNewsRepository,
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


@router.post("/tracked")
async def mark_tracked(
    request: schemas.TrackedRequest,
    opportunity_repository: repositories.OpportunityRepository = Depends(
        get_opportunity_repository
    ),
) -> schemas.OkResponse:
    """Notes that someone did an opportunity, so Mein Impact follows it.

    Stores one mark per opportunity, nothing about the caller. The access
    log skips this path (`main.py`).
    """
    found = await opportunity_repository.mark_tracked(
        request.opportunity_id, datetime.now(UTC).date()
    )
    if not found:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Opportunity not found."
        )
    await opportunity_repository.commit()
    return schemas.OkResponse()


@router.get("/news")
async def get_impact_news(
    news_repository: PostgresImpactNewsRepository = Depends(get_impact_news_repository),
) -> schemas.ImpactNewsFeedResponse:
    """News on every tracked opportunity, for the app's Mein Impact view.

    The whole feed, never one opportunity: asking for one would tell the
    server which action the caller did.
    """
    feed = await news_repository.feed()
    return schemas.ImpactNewsFeedResponse(
        opportunities=[
            schemas.ImpactNewsEntryResponse(
                opportunity_id=opportunity_id,
                checked_at=news.checked_at,
                items=[
                    schemas.ImpactNewsItemResponse(
                        level=i.level,
                        kind=i.kind,
                        title=i.title,
                        url=i.url,
                        snippet=i.snippet,
                        published_on=i.published_on,
                    )
                    for i in news.shown
                ],
            )
            for opportunity_id, news in feed.items()
            if news.checked_at is not None
        ]
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
