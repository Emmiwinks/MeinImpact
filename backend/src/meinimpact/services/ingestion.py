"""Composition root for opportunity ingestion.

The only place that knows which concrete parts make up a production run:
the configured registries and detail readers, Mistral enrichment and the
Postgres store. Everything it wires is replaceable on its own.
"""

from meinimpact.core.config import Settings
from meinimpact.infrastructure.ai.listing_enricher import ListingEnricher
from meinimpact.infrastructure.ai.mistral_json import MistralJsonCompleter
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.listings.catalog import (
    default_detail_readers,
    default_sources,
)
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
)
from meinimpact.infrastructure.pipeline.ingestion import (
    IngestionSummary,
    run_ingestion,
)


class IngestionNotConfiguredError(RuntimeError):
    """Raised when a required provider key is missing."""


async def run_configured_ingestion(settings: Settings) -> IngestionSummary:
    if not settings.mistral_api_key:
        raise IngestionNotConfiguredError(
            "Ingestion requires MEINIMPACT_MISTRAL_API_KEY"
        )
    completer = MistralJsonCompleter(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=settings.mistral_extraction_model,
    )
    database = Database(settings.database_url)
    try:
        async with (
            PoliteHttpClient() as http,
            database.session_factory() as session,
        ):
            return await run_ingestion(
                sources=default_sources(http),
                detail_readers=default_detail_readers(http),
                enricher=ListingEnricher(completer),
                store=PostgresOpportunityRepository(session),
            )
    finally:
        await completer.aclose()
        await database.close()
