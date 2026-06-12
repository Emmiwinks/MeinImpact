"""Anonymous user feedback route."""

from fastapi import APIRouter, Depends

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_feedback_repository, require_principal
from meinimpact.domain import repositories

router = APIRouter(
    prefix="/v1",
    tags=["feedback"],
    dependencies=[Depends(require_principal)],
)


@router.post("/feedback")
async def submit_feedback(
    request: schemas.FeedbackRequest,
    feedback_repo: repositories.FeedbackRepository = Depends(get_feedback_repository),
) -> schemas.OkResponse:
    """Records anonymous feedback for an action or the app."""
    await feedback_repo.submit(
        action_id=request.action_id,
        rating=request.rating,
        comment=request.comment,
    )
    return schemas.OkResponse()
