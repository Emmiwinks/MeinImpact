"""Admin operational routes.

A run reads several registries politely and enriches new listings with an
LLM, which takes minutes, so the route starts it in the background and
returns at once. Only one run at a time across all machines (the run row in
the database is the lock). The same runs can be started and scheduled from
the /admin page (`admin_portal.py`).
"""

import logging
import secrets

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException, status

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_ingestion_runs
from meinimpact.core.config import Settings, get_settings
from meinimpact.services.ingestion_runs import IngestionRuns

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/admin", tags=["admin"])


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
    runs: IngestionRuns = Depends(get_ingestion_runs),
) -> schemas.IngestionRunResponse:
    """Starts an ingestion run in the background; the result is recorded."""
    if not settings.mistral_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Ingestion requires MEINIMPACT_MISTRAL_API_KEY to be configured",
        )
    run_id = await runs.claim("manual")
    if run_id is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An ingestion run is already in progress",
        )
    background_tasks.add_task(runs.execute, run_id)
    return schemas.IngestionRunResponse(status="started")
