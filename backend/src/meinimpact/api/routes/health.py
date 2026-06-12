"""Health API routes."""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends

from meinimpact.api import schemas
from meinimpact.core.config import Settings, get_settings

router = APIRouter(tags=["health"])

APP_VERSION_MIN = "1.0.0"


@router.get("/health")
def health(settings: Settings = Depends(get_settings)) -> schemas.HealthResponse:
    """Single health endpoint with pool_version and app_version_min."""
    return schemas.HealthResponse(
        status="ok",
        service=settings.app_name,
        version=settings.api_version,
        pool_version=datetime.now(UTC).strftime("%Y-%m-%d"),
        app_version_min=APP_VERSION_MIN,
    )


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
