"""Civic action API routes."""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import (
    get_action_repository,
    get_action_stats_repository,
    get_ai_generator,
    get_recommendation_service,
    get_tracking_repository,
    require_principal,
)
from meinimpact.domain import repositories
from meinimpact.infrastructure.ai.base import AiTextGenerator
from meinimpact.services.context_service import ContextService
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


@router.get("/pool")
async def get_action_pool(
    action_repository: repositories.CivicActionRepository = Depends(
        get_action_repository
    ),
) -> schemas.ActionPoolResponse:
    """Returns the full action pool for device-side scoring."""
    actions = await action_repository.list_open_actions()
    now = datetime.now(UTC)
    return schemas.ActionPoolResponse(
        actions=[schemas.ActionPoolItemResponse.from_domain(a) for a in actions],
        version=now.strftime("%Y-%m-%d"),
        generated_at=now,
    )


@router.post("/{action_id}/context")
async def get_action_context(
    action_id: str,
    request: schemas.ActionContextRequest,
    action_repository: repositories.CivicActionRepository = Depends(
        get_action_repository
    ),
    ai_generator: AiTextGenerator = Depends(get_ai_generator),
) -> schemas.ActionContextResponse:
    """Returns AI-generated personalised context for an action."""
    action = await action_repository.get_action(action_id)
    if action is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "Action not found", "code": "NOT_FOUND"},
        )
    service = ContextService(ai_generator)
    try:
        context_text = await service.generate(action, request)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": "AI generation temporarily unavailable",
                "code": "AI_UNAVAILABLE",
                "fallback": True,
            },
        )
    return schemas.ActionContextResponse(action_id=action_id, context=context_text)


@router.post("/{action_id}/complete")
async def complete_action(
    action_id: str,
    request: schemas.ActionCompleteRequest,
    action_repository: repositories.CivicActionRepository = Depends(
        get_action_repository
    ),
    stats_repository: repositories.ActionStatsRepository = Depends(
        get_action_stats_repository
    ),
) -> schemas.ActionCompleteResponse:
    """Records an anonymous action completion and returns the updated total."""
    action = await action_repository.get_action(action_id)
    if action is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "Action not found", "code": "NOT_FOUND"},
        )
    count = await stats_repository.increment_completion(action_id)
    return schemas.ActionCompleteResponse(ok=True, completion_count=count)


@router.get("/{action_id}/tracking")
async def get_action_tracking(
    action_id: str,
    action_repository: repositories.CivicActionRepository = Depends(
        get_action_repository
    ),
    tracking_repository: repositories.TrackingRepository = Depends(
        get_tracking_repository
    ),
) -> schemas.ActionTrackingResponse:
    """Returns tracking events and MdB statements for an action."""
    action = await action_repository.get_action(action_id)
    if action is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "Action not found", "code": "NOT_FOUND"},
        )
    events = await tracking_repository.list_events(action_id)
    statements = await tracking_repository.list_mdb_statements(action_id)
    return schemas.ActionTrackingResponse(
        action_id=action_id,
        events=[schemas.TrackingEventResponse.from_domain(e) for e in events],
        mdb_statements=[schemas.MdbStatementResponse.from_domain(s) for s in statements],
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
