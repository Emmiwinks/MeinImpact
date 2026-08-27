"""Admin operational routes.

Currently exposes one thing: a manual trigger for the ingestion procedure
that APScheduler otherwise runs once a day (see `main.py`'s "daily_ingestion"
job). Both call the exact same `run_ingestion_pipeline` function — there is
only one definition of the procedure, this route just lets it be fired on
demand for verification/demos instead of waiting for 03:00 CET.
"""

import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_db_session
from meinimpact.core.config import Settings, get_settings
from meinimpact.infrastructure.pipeline.orchestrator import run_ingestion_pipeline

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


@router.post("/ingestion/run", dependencies=[Depends(require_admin)])
async def trigger_ingestion_run(
    settings: Settings = Depends(get_settings),
    session: AsyncSession = Depends(get_db_session),
) -> schemas.PipelineRunResponse:
    """Runs the ingestion procedure now and returns its `pipeline_runs` row."""
    await run_ingestion_pipeline(settings)
    result = await session.execute(
        text(
            "SELECT id, ran_at, parliamentary_actions_found, petition_actions_found, "
            "state_a_count, state_b_count, state_c_count, state_d_discarded, "
            "inserted_count, duration_seconds, errors "
            "FROM pipeline_runs ORDER BY ran_at DESC LIMIT 1"
        )
    )
    row = result.mappings().first()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Ingestion run produced no pipeline_runs row",
        )
    return schemas.PipelineRunResponse(**row)
