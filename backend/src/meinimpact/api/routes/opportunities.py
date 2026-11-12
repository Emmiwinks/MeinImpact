"""Civic opportunity routes: the feed's single data source.

One opportunity is one registry entry (a petition, a consultation, a
Bauleitplan display...), so the pool response already carries everything
the feed card and its detail view need. No separate detail endpoint; only
council decisions have one more: the recipients of a letter. `tracked`
takes the app's anonymous mark that someone did an opportunity; `news`
serves what Mein Impact found on all tracked ones.
"""

from collections.abc import Sequence
from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import (
    get_council_repository,
    get_impact_news_repository,
    get_opportunity_repository,
    require_principal,
)
from meinimpact.domain import repositories
from meinimpact.domain.entities import Opportunity
from meinimpact.infrastructure.ai.taxonomy import TAG_AXES
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

# The landing page reads this one without a session.
public_router = APIRouter(prefix="/v1/opportunities", tags=["opportunities"])

PREVIEW_SIZE = 12
# Dresden first: the page is for people who live there.
_PREVIEW_REGIONS = ("dresden", "sachsen", "bund", "eu")
_TOPICS = list(TAG_AXES)


def _easy(opportunity: Opportunity) -> bool:
    """Everyday and easy to grasp, so a stranger gets it at a glance."""
    return (opportunity.everyday_relevance or 0) >= 4 and (
        opportunity.accessibility or 0
    ) >= 4


def preview_selection(opportunities: Sequence[Opportunity]) -> list[Opportunity]:
    """Easy questions, soonest deadline first per level, levels taking turns."""
    queues = {
        region: sorted(
            (o for o in opportunities if o.region == region and _easy(o)),
            key=lambda o: (o.closes_on is None, o.closes_on),
        )
        for region in _PREVIEW_REGIONS
    }
    picked: list[Opportunity] = []
    while len(picked) < PREVIEW_SIZE and any(queues.values()):
        for region in _PREVIEW_REGIONS:
            if queues[region] and len(picked) < PREVIEW_SIZE:
                picked.append(queues[region].pop(0))
    return picked


def _topic_index(opportunity: Opportunity) -> int | None:
    tags = opportunity.affected_tags
    return _TOPICS.index(tags[0]) if tags and tags[0] in _TOPICS else None


@public_router.get("/preview")
async def get_opportunity_preview(
    response: Response,
    opportunity_repository: repositories.OpportunityRepository = Depends(
        get_opportunity_repository
    ),
) -> schemas.OpportunityPreviewResponse:
    """Counts and a few open questions for meinimpact.de."""
    now = datetime.now(UTC)
    opportunities = await opportunity_repository.list_open(now.date())
    response.headers["Cache-Control"] = "public, max-age=900"
    return schemas.OpportunityPreviewResponse(
        total=len(opportunities),
        by_region={
            region: sum(1 for o in opportunities if o.region == region)
            for region in _PREVIEW_REGIONS
        },
        items=[
            schemas.OpportunityPreviewItemResponse(
                title=o.title,
                kind=o.kind,
                region=o.region,
                source_org=o.source_org,
                summary=o.summary,
                opens_on=o.opens_on,
                closes_on=o.closes_on,
                topic_index=_topic_index(o),
                for_you=next(iter(o.personal_impact_snippets.values()), None),
                pro_argumente=list(o.pro_argumente),
                contra_argumente=list(o.contra_argumente),
                support_count=o.support_count,
                support_goal=o.support_goal,
                place=o.organizer or o.locality,
                districts=list(o.districts),
            )
            for o in preview_selection(opportunities)
        ],
        generated_at=now,
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
