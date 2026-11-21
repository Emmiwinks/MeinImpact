"""FastAPI dependency factories."""

from collections.abc import AsyncIterator
from functools import cache

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.core.config import Settings, get_settings
from meinimpact.domain import repositories
from meinimpact.infrastructure.ai.base import AiTextGenerator
from meinimpact.infrastructure.ai.dummy_generator import DummyTextGenerator
from meinimpact.infrastructure.ai.mistral_client import MistralTextGenerator
from meinimpact.infrastructure.council.postgres_council_repository import (
    PostgresCouncilRepository,
)
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.geo.locality import LocalityResolver
from meinimpact.infrastructure.geo.plz import PlzIndex
from meinimpact.infrastructure.impact.postgres_news_repository import (
    PostgresImpactNewsRepository,
)
from meinimpact.infrastructure.listings.catalog import default_locality_resolver
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
)
from meinimpact.infrastructure.security.tokens import (
    Principal,
    TokenError,
    TokenService,
)
from meinimpact.infrastructure.usage.postgres_usage_repository import (
    PostgresUsageRepository,
)
from meinimpact.services.draft_service import DraftService
from meinimpact.services.ingestion_runs import IngestionRuns

_bearer_scheme = HTTPBearer(auto_error=False)

_db: Database | None = None


def get_token_service(settings: Settings = Depends(get_settings)) -> TokenService:
    """Returns a token service configured from application settings."""
    return TokenService(
        secret=settings.jwt_secret,
        issuer=settings.jwt_issuer,
        audience=settings.jwt_audience,
        access_token_minutes=settings.access_token_minutes,
    )


def require_principal(
    credentials: HTTPAuthorizationCredentials | None = Security(_bearer_scheme),
    token_service: TokenService = Depends(get_token_service),
) -> Principal:
    """Validates the bearer token and returns the caller principal."""
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token.",
        )
    try:
        return token_service.verify_access_token(credentials.credentials)
    except TokenError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token.",
        ) from error


def get_database(settings: Settings = Depends(get_settings)) -> Database:
    """Returns the process-wide database, created on first use."""
    global _db
    if _db is None:
        _db = Database(settings.database_url)
    return _db


async def get_db_session(
    database: Database = Depends(get_database),
) -> AsyncIterator[AsyncSession]:
    """Yields one database session per request."""
    async for session in database.session():
        yield session


def get_ingestion_runs(
    database: Database = Depends(get_database),
    settings: Settings = Depends(get_settings),
) -> IngestionRuns:
    """Returns the service behind manual and scheduled ingestion runs."""
    return IngestionRuns(database, settings)


def get_opportunity_repository(
    session: AsyncSession = Depends(get_db_session),
) -> repositories.OpportunityRepository:
    """Returns the PostgreSQL-backed opportunity repository."""
    return PostgresOpportunityRepository(session)


def get_council_repository(
    session: AsyncSession = Depends(get_db_session),
) -> PostgresCouncilRepository:
    """Returns the PostgreSQL-backed council member repository."""
    return PostgresCouncilRepository(session)


def get_impact_news_repository(
    session: AsyncSession = Depends(get_db_session),
) -> PostgresImpactNewsRepository:
    """Returns the PostgreSQL-backed Mein Impact news repository."""
    return PostgresImpactNewsRepository(session)


def get_usage_repository(
    session: AsyncSession = Depends(get_db_session),
) -> PostgresUsageRepository:
    """Returns the PostgreSQL-backed anonymous usage counters."""
    return PostgresUsageRepository(session)


@cache
def get_plz_index() -> PlzIndex:
    """Returns the committed PLZ table, loaded on first use."""
    return PlzIndex.load()


@cache
def get_locality_resolver() -> LocalityResolver:
    """Returns the resolver that locates opportunities, built on first use."""
    return default_locality_resolver(get_plz_index())


def get_ai_generator(settings: Settings = Depends(get_settings)) -> AiTextGenerator:
    """Returns the configured AI text generator."""
    if settings.mistral_api_key:
        return MistralTextGenerator(
            api_key=settings.mistral_api_key,
            base_url=settings.mistral_base_url,
            model=settings.mistral_model,
        )
    return DummyTextGenerator()


def get_draft_service(
    ai_generator: AiTextGenerator = Depends(get_ai_generator),
) -> DraftService:
    """Returns the AI draft service."""
    return DraftService(ai_generator)
