"""FastAPI application factory."""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from meinimpact.api.routes import (
    actions,
    auth,
    beta,
    feedback,
    health,
    letters,
    mdb,
    news,
    push,
)
from meinimpact.core.config import Settings, get_settings
from meinimpact.core.middleware import (
    RequestSizeLimitMiddleware,
    SecurityHeadersMiddleware,
)
from meinimpact.infrastructure.mdb.wks_service import WksService
from meinimpact.infrastructure.pipeline.orchestrator import run_ingestion_pipeline

logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    """Creates and configures the FastAPI app."""
    resolved_settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        wks = WksService()
        await wks.load()
        if not wks.is_healthy:
            logger.critical(
                "WKS SERVICE DID NOT LOAD — /v1/mdb will return 503. Error: %s",
                wks.load_error,
            )
        app.state.wks_service = wks

        scheduler = AsyncIOScheduler()
        scheduler.add_job(
            run_ingestion_pipeline,
            CronTrigger(hour=3, minute=0, timezone="Europe/Berlin"),
            args=[resolved_settings],
            id="daily_ingestion",
            replace_existing=True,
        )
        scheduler.start()
        logger.info("Ingestion scheduler started (daily 03:00 CET)")

        try:
            yield
        finally:
            scheduler.shutdown(wait=False)
            logger.info("Ingestion scheduler stopped")

    app = FastAPI(
        title=resolved_settings.app_name,
        version=resolved_settings.api_version,
        docs_url="/docs" if resolved_settings.environment != "production" else None,
        redoc_url="/redoc" if resolved_settings.environment != "production" else None,
        lifespan=lifespan,
    )
    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(
        RequestSizeLimitMiddleware,
        max_body_bytes=resolved_settings.max_request_body_bytes,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=resolved_settings.allowed_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
    )
    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(actions.router)
    app.include_router(letters.router)
    app.include_router(mdb.router)
    app.include_router(news.router)
    app.include_router(push.router)
    app.include_router(feedback.router)
    app.include_router(beta.router)
    return app


app = create_app()
