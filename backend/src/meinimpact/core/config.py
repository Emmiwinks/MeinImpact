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
    # Listing enrichment needs reliable multi-constraint structured output,
    # which mistral-small did not deliver in calibration. Separate from
    # mistral_model, which stays small/cheap for letter-draft generation.
    mistral_extraction_model: str = "mistral-medium-latest"
    mistral_base_url: str = "https://api.mistral.ai/v1"
    # Unused by any pipeline for now — DipAdapter is preserved unwired in
    # infrastructure/sources/dip_adapter.py in case a later project stage
    # needs it again. See specs/data/ingestion-pipeline.md "Status".
    dip_api_key: str | None = None
    tavily_api_key: str | None = None
    newsdata_api_key: str | None = None
    max_request_body_bytes: int = 65_536
    admin_api_key: str | None = None
    # Password for the /admin page. Unset means the page rejects every login.
    admin_password: str | None = None
    admin_session_hours: int = 12
    # Off by default so local dev never spends Mistral credit on its own;
    # production turns it on in fly.toml. The interval is set on /admin.
    ingestion_scheduler_enabled: bool = False
    ingestion_check_minutes: int = 15
    # Mein Impact news for tracked opportunities (services/impact_news.py).
    # Off by default like ingestion; fly.toml turns it on.
    impact_news_enabled: bool = False
    impact_news_check_minutes: int = 60
    impact_news_daily_budget_eur: float = 1.0
    # Search an opportunity again at most this often
    impact_news_recheck_days: int = 7
    # Prices looked up 2026-11-11 in USD, counted 1:1 as EUR (overstates a
    # little, the safe side for a budget). Tavily pay-as-you-go, basic
    # search = 1 credit; Mistral Medium 3.5 per million tokens.
    tavily_eur_per_credit: float = 0.008
    mistral_extraction_eur_per_m_input: float = 1.5
    mistral_extraction_eur_per_m_output: float = 7.5

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="MEINIMPACT_",
        extra="ignore",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Returns cached application settings."""
    return Settings()
