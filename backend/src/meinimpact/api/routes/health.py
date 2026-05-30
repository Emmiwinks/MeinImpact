"""Health API routes."""

from fastapi import APIRouter, Depends

from meinimpact.api import schemas
from meinimpact.core.config import Settings, get_settings

router = APIRouter(tags=["health"])


@router.get("/health/live")
def live(settings: Settings = Depends(get_settings)) -> schemas.HealthResponse:
    """Returns process liveness."""
    return schemas.HealthResponse(
        status="ok",
        service=settings.app_name,
        version=settings.api_version,
    )


@router.get("/health/ready")
def ready(settings: Settings = Depends(get_settings)) -> schemas.HealthResponse:
    """Returns basic readiness for the stateless API process."""
    return schemas.HealthResponse(
        status="ok",
        service=settings.app_name,
        version=settings.api_version,
    )
