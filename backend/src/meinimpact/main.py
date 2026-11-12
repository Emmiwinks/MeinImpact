"""FastAPI application factory."""

import asyncio
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager, suppress
from datetime import timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from meinimpact.api.dependencies import get_database
from meinimpact.api.routes import (
    actions,
    admin,
    admin_portal,
    auth,
    beta,
    feedback,
    health,
    letters,
    mdb,
    news,
    opportunities,
    push,
)
from meinimpact.core.config import Settings, get_settings
from meinimpact.core.middleware import (
    RequestSizeLimitMiddleware,
    SecurityHeadersMiddleware,
)
from meinimpact.infrastructure.mdb.wks_service import WksService
from meinimpact.services.impact_news import run_news_scheduler
from meinimpact.services.ingestion_runs import IngestionRuns, run_scheduler

logger = logging.getLogger(__name__)

# Requests the access log must never show, so no log line ties a caller's
# address to having done an action.
_UNLOGGED_PATHS = frozenset({"/v1/opportunities/tracked"})


class _SkipUnloggedPaths(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        # uvicorn's access record args: client, method, path, version, status
        args = record.args
        if isinstance(args, tuple) and len(args) >= 3:
            return str(args[2]).split("?", 1)[0] not in _UNLOGGED_PATHS
        return True


_skip_unlogged_paths = _SkipUnloggedPaths()


def create_app(settings: Settings | None = None) -> FastAPI:
    """Creates and configures the FastAPI app."""
    resolved_settings = settings or get_settings()
    # addFilter ignores a filter that is already attached
    logging.getLogger("uvicorn.access").addFilter(_skip_unlogged_paths)

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

        # Every machine checks; the run row in the database makes sure only
        # one of them actually ingests. Interval and on/off live on /admin.
        scheduler: asyncio.Task[None] | None = None
        if resolved_settings.ingestion_scheduler_enabled:
            scheduler = asyncio.create_task(
                run_scheduler(
                    IngestionRuns(get_database(resolved_settings), resolved_settings),
                    timedelta(minutes=resolved_settings.ingestion_check_minutes),
                )
            )

        # Mein Impact news within the daily budget; claims in the database
        # keep two machines off the same opportunity (services/impact_news).
        news_scheduler: asyncio.Task[None] | None = None
        if resolved_settings.impact_news_enabled:
            news_scheduler = asyncio.create_task(
                run_news_scheduler(
                    resolved_settings,
                    get_database(resolved_settings),
                    timedelta(minutes=resolved_settings.impact_news_check_minutes),
                )
            )

        yield

        for task in (scheduler, news_scheduler):
            if task is not None:
                task.cancel()
                with suppress(asyncio.CancelledError):
                    await task

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
    app.include_router(opportunities.public_router)
    app.include_router(opportunities.router)
    app.include_router(letters.router)
    app.include_router(mdb.router)
    app.include_router(news.router)
    app.include_router(push.router)
    app.include_router(feedback.router)
    app.include_router(beta.router)
    app.include_router(admin.router)
    app.include_router(admin_portal.router)
    app.dependency_overrides[get_settings] = lambda: resolved_settings
    return app


app = create_app()
