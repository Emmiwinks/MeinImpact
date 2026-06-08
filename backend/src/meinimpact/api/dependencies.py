"""FastAPI dependency factories."""

from collections.abc import AsyncIterator

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.core.config import Settings, get_settings
from meinimpact.domain import repositories
from meinimpact.infrastructure.actions.postgres_action_repository import (
    PostgresActionRepository,
)
from meinimpact.infrastructure.ai.base import AiTextGenerator
from meinimpact.infrastructure.ai.dummy_generator import DummyTextGenerator
from meinimpact.infrastructure.ai.mistral_client import MistralTextGenerator
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.news.dummy_news_repository import DummyNewsRepository
from meinimpact.infrastructure.security.tokens import (
    Principal,
    TokenError,
    TokenService,
)
from meinimpact.services.draft_service import DraftService
from meinimpact.services.recommendation_service import RecommendationService

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


async def get_db_session(
    settings: Settings = Depends(get_settings),
) -> AsyncIterator[AsyncSession]:
    """Yields one database session per request."""
    global _db
    if _db is None:
        _db = Database(settings.database_url)
    async for session in _db.session():
        yield session


def get_action_repository(
    session: AsyncSession = Depends(get_db_session),
) -> repositories.CivicActionRepository:
    """Returns the PostgreSQL-backed civic action repository."""
    return PostgresActionRepository(session)


def get_news_repository() -> repositories.NewsRepository:
    """Returns the current news repository."""
    return DummyNewsRepository()


def get_ai_generator(settings: Settings = Depends(get_settings)) -> AiTextGenerator:
    """Returns the configured AI text generator."""
    if settings.mistral_api_key:
        return MistralTextGenerator(
            api_key=settings.mistral_api_key,
            base_url=settings.mistral_base_url,
            model=settings.mistral_model,
        )
    return DummyTextGenerator()


def get_recommendation_service(
    action_repository: repositories.CivicActionRepository = Depends(
        get_action_repository
    ),
) -> RecommendationService:
    """Returns the action recommendation service."""
    return RecommendationService(action_repository)


def get_draft_service(
    ai_generator: AiTextGenerator = Depends(get_ai_generator),
) -> DraftService:
    """Returns the AI draft service."""
    return DraftService(ai_generator)
