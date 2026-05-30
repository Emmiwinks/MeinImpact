"""Authentication API routes."""

from fastapi import APIRouter, Depends, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_token_service
from meinimpact.infrastructure.security.tokens import TokenService

router = APIRouter(prefix="/v1/auth", tags=["auth"])


@router.post(
    "/anonymous-session",
    status_code=status.HTTP_201_CREATED,
)
def create_anonymous_session(
    request: schemas.AnonymousSessionRequest,
    token_service: TokenService = Depends(get_token_service),
) -> schemas.TokenResponse:
    """Creates an anonymous installation-scoped API session."""
    token_pair = token_service.create_anonymous_session(
        installation_id=str(request.installation_id),
        app_version=request.app_version,
    )
    return schemas.TokenResponse(
        access_token=token_pair.access_token,
        refresh_token=token_pair.refresh_token,
        expires_in_seconds=token_pair.expires_in_seconds,
    )
