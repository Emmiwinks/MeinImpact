"""Admin operational routes.

Ingestion is trigger-based only (no scheduled job). A run reads several
registries politely and enriches new listings with an LLM, which takes
minutes, so the route starts it in the background and returns at once.
Only one run at a time.
"""

import asyncio
import logging
import secrets

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException, status

from meinimpact.api import schemas
from meinimpact.core.config import Settings, get_settings
from meinimpact.services.ingestion import run_configured_ingestion

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/admin", tags=["admin"])

_ingestion_lock = asyncio.Lock()


def require_admin(
    x_admin_api_key: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> None:
    """Guards admin routes with a shared-secret header.

    Fails closed: if MEINIMPACT_ADMIN_API_KEY isn't configured, every request
    is rejected rather than the route being open by default.
    """
    configured = settings.admin_api_key
    if (
        not configured
        or not x_admin_api_key
        or not secrets.compare_digest(x_admin_api_key, configured)
    ):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")


@router.post(
    "/ingestion/run",
    dependencies=[Depends(require_admin)],
    status_code=status.HTTP_202_ACCEPTED,
)
async def trigger_ingestion_run(
    background_tasks: BackgroundTasks,
    settings: Settings = Depends(get_settings),
) -> schemas.IngestionRunResponse:
    """Starts an ingestion run in the background; the summary is logged."""
    if not settings.mistral_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Ingestion requires MEINIMPACT_MISTRAL_API_KEY to be configured",
        )
    if _ingestion_lock.locked():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An ingestion run is already in progress",
        )
    await _ingestion_lock.acquire()
    background_tasks.add_task(_run_and_release, settings)
    return schemas.IngestionRunResponse(status="started")


async def _run_and_release(settings: Settings) -> None:
    try:
        summary = await run_configured_ingestion(settings)
        logger.info("Admin-triggered ingestion finished: %s", summary)
    except Exception:
        logger.exception("Admin-triggered ingestion failed")
    finally:
        _ingestion_lock.release()
