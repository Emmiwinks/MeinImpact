"""Civic action API routes."""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import (
    get_action_repository,
    get_recommendation_service,
    require_principal,
)
from meinimpact.domain import repositories
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
    return schemas.ActionPoolResponse(
        actions=[schemas.ActionPoolItemResponse.from_domain(a) for a in actions],
        version=datetime.now(UTC).strftime("%Y-%m-%d"),
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
