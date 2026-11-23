"""Beta feedback from the app, shown on /admin/feedback.

Card reasons say why a tester threw a card away and how the app had ranked
it; messages are free text from the profile. The server keeps a tester
pseudonym (services/beta_feedback.py) and the day, nothing about the
profile. Never sent to an LLM.
"""

from fastapi import APIRouter, Depends

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_feedback_repository, require_principal
from meinimpact.core.config import Settings, get_settings
from meinimpact.infrastructure.feedback.postgres_feedback_repository import (
    CardFeedback,
    Message,
    PostgresFeedbackRepository,
)
from meinimpact.infrastructure.security.tokens import Principal
from meinimpact.services.beta_feedback import pseudonym, today

router = APIRouter(prefix="/v1/feedback", tags=["feedback"])


@router.post("/card")
async def card_feedback(
    request: schemas.CardFeedbackRequest,
    principal: Principal = Depends(require_principal),
    settings: Settings = Depends(get_settings),
    feedback: PostgresFeedbackRepository = Depends(get_feedback_repository),
) -> schemas.OkResponse:
    """Keeps why a card was thrown away."""
    await feedback.add_card(
        CardFeedback(
            tester=pseudonym(principal.installation_id, settings.jwt_secret),
            day=today(),
            opportunity_id=request.opportunity_id,
            reason=request.reason,
            note=_clean(request.note),
            ranking=request.ranking.model_dump(),
            app_version=request.app_version,
        )
    )
    await feedback.commit()
    return schemas.OkResponse()


@router.post("")
async def message(
    request: schemas.BetaFeedbackRequest,
    principal: Principal = Depends(require_principal),
    settings: Settings = Depends(get_settings),
    feedback: PostgresFeedbackRepository = Depends(get_feedback_repository),
) -> schemas.OkResponse:
    """Keeps a free-text message from a tester."""
    await feedback.add_message(
        Message(
            tester=pseudonym(principal.installation_id, settings.jwt_secret),
            day=today(),
            kind=request.kind,
            message=request.message,
            screen=request.screen,
            app_version=request.app_version,
            platform=request.platform,
        )
    )
    await feedback.commit()
    return schemas.OkResponse()


def _clean(note: str | None) -> str | None:
    stripped = (note or "").strip()
    return stripped or None
