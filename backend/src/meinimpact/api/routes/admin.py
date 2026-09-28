"""Admin operational routes.

Exposes a manual trigger for the ingestion pipeline. Ingestion is
trigger-based only (no scheduled job) — see
specs/data/ingestion-pipeline.md "Status".
"""

import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.api import schemas
from meinimpact.api.dependencies import get_db_session
from meinimpact.core.config import Settings, get_settings
from meinimpact.infrastructure.ai.embeddings import MistralEmbeddingClient
from meinimpact.infrastructure.ai.opportunity_extractor import OpportunityExtractor
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
)
from meinimpact.infrastructure.pipeline.opportunity_pipeline import run_ingestion
from meinimpact.infrastructure.sources.tavily_client import TavilyClient
from meinimpact.infrastructure.sources.tavily_opportunity_adapter import (
    TavilyOpportunityAdapter,
)

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
) -> schemas.IngestionRunResponse:
    """Runs the opportunity ingestion pipeline now, for every region."""
    if not settings.tavily_api_key or not settings.mistral_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Ingestion requires MEINIMPACT_TAVILY_API_KEY and "
            "MEINIMPACT_MISTRAL_API_KEY to be configured",
        )

    source = TavilyOpportunityAdapter(TavilyClient(settings.tavily_api_key))
    extractor = OpportunityExtractor(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=settings.mistral_extraction_model,
    )
    embedder = MistralEmbeddingClient(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=settings.mistral_embedding_model,
    )
    repository = PostgresOpportunityRepository(session)

    summary = await run_ingestion(
        source=source, extractor=extractor, embedder=embedder, repository=repository
    )
    return schemas.IngestionRunResponse(
        fetched=summary.fetched,
        actionable=summary.actionable,
        inserted=summary.inserted,
        refreshed=summary.refreshed,
        errors=summary.errors,
    )
