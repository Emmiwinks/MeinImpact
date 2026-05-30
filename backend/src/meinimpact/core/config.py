"""Application settings."""

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime settings loaded from environment variables."""

    app_name: str = "MeinImpact API"
    api_version: str = "v1"
    environment: str = "local"
    allowed_origins: list[str] = Field(
        default_factory=lambda: [
            "http://localhost:3000",
            "http://localhost:5173",
            "http://localhost:8000",
        ]
    )
    database_url: str = (
        "postgresql+asyncpg://meinimpact:meinimpact@localhost:5432/meinimpact"
    )
    jwt_secret: str = "replace-this-local-development-secret"
    jwt_issuer: str = "meinimpact-api"
    jwt_audience: str = "meinimpact-app"
    access_token_minutes: int = 15
    mistral_api_key: str | None = None
    mistral_model: str = "mistral-small-latest"
    mistral_base_url: str = "https://api.mistral.ai/v1"
    max_request_body_bytes: int = 65_536

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="MEINIMPACT_",
        extra="ignore",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Returns cached application settings."""
    return Settings()
