"""Civic action API routes."""

from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse

from meinimpact.api import schemas, sse
from meinimpact.api.dependencies import (
    get_action_repository,
    get_draft_service,
    get_recommendation_service,
    require_principal,
)
from meinimpact.domain import repositories
from meinimpact.services.draft_service import DraftService
from meinimpact.services.recommendation_service import RecommendationService

router = APIRouter(
    prefix="/v1/actions",
    tags=["actions"],
    dependencies=[Depends(require_principal)],
)


@router.post("/recommendations")
async def recommend_actions(
    request: schemas.RecommendationsRequest,
    recommendation_service: RecommendationService = Depends(get_recommendation_service),
) -> schemas.RecommendationsResponse:
    """Returns transparent action recommendations for a user profile."""
    recommendations = await recommendation_service.recommend(
        profile=request.profile.to_domain(),
        limit=request.limit,
    )
    return schemas.RecommendationsResponse(
        recommendations=[
            schemas.RecommendationResponse.from_domain(recommendation)
            for recommendation in recommendations
        ]
    )


@router.get("/{action_id}")
async def get_action(
    action_id: str,
    action_repository: repositories.CivicActionRepository = Depends(
        get_action_repository
    ),
) -> schemas.ActionResponse:
    """Returns one civic action."""
    action = await action_repository.get_action(action_id)
    if action is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Action not found.",
        )
    return schemas.ActionResponse.from_domain(action)


@router.post("/{action_id}/drafts/stream")
async def stream_action_draft(
    action_id: str,
    request: schemas.DraftRequest,
    action_repository: repositories.CivicActionRepository = Depends(
        get_action_repository
    ),
    draft_service: DraftService = Depends(get_draft_service),
) -> StreamingResponse:
    """Streams an AI-assisted civic action draft as SSE."""
    action = await action_repository.get_action(action_id)
    if action is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Action not found.",
        )

    async def event_stream() -> AsyncIterator[str]:
        yield sse.encode_json_sse("draft.started", {"action_id": action.id})
        async for delta in draft_service.stream_draft(
            action=action,
            profile=request.profile.to_domain(),
            personal_context=request.personal_context,
            tone=request.tone,
        ):
            yield sse.encode_json_sse("draft.delta", {"text": delta})
        yield sse.encode_json_sse("draft.completed", {"action_id": action.id})

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-store"},
    )
