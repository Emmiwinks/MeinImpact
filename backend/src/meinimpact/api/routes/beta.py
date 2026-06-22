"""Beta token activation route."""

from fastapi import APIRouter, Depends, HTTPException, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_beta_repository
from meinimpact.domain import repositories

router = APIRouter(prefix="/v1/beta", tags=["beta"])


@router.post("/activate")
async def activate_beta_token(
    request: schemas.BetaActivateRequest,
    beta_repo: repositories.BetaTokenRepository = Depends(get_beta_repository),
) -> schemas.BetaActivateResponse:
    """Validates and activates a beta access token."""
    valid = await beta_repo.activate(request.token)
    if not valid:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": "Token not found or already used",
                "code": "TOKEN_INVALID",
            },
        )
    return schemas.BetaActivateResponse(valid=True)
