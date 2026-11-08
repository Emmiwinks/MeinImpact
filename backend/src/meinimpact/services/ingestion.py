"""Composition root for opportunity ingestion.

The only place that knows which concrete parts make up a production run:
the configured registries and detail readers, Mistral enrichment and the
Postgres store. Everything it wires is replaceable on its own.
"""

import logging
from datetime import UTC, datetime, timedelta

from meinimpact.core.config import Settings
from meinimpact.infrastructure.ai.listing_enricher import ListingEnricher
from meinimpact.infrastructure.ai.mistral_json import MistralJsonCompleter
from meinimpact.infrastructure.council.offices import FRAKTION_OFFICES
from meinimpact.infrastructure.council.oparl_members import fetch_council_members
from meinimpact.infrastructure.council.postgres_council_repository import (
    PostgresCouncilRepository,
)
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.geo.districts import CITIES, DistrictMatcher
from meinimpact.infrastructure.listings.catalog import (
    default_detail_readers,
    default_sources,
)
from meinimpact.infrastructure.listings.http import PoliteHttpClient
from meinimpact.infrastructure.listings.model import Region
from meinimpact.infrastructure.listings.sources import oparl
from meinimpact.infrastructure.listings.sources.oparl import OParlBody
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
)
from meinimpact.infrastructure.pipeline.ingestion import (
    IngestionSummary,
    run_ingestion,
)

logger = logging.getLogger(__name__)

MEMBER_SYNC_INTERVAL = timedelta(days=7)


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
            summary = await run_ingestion(
                sources=default_sources(http),
                detail_readers=default_detail_readers(http),
                enricher=ListingEnricher(
                    completer,
                    {Region.DRESDEN: DistrictMatcher.for_city(CITIES["dresden"])},
                ),
                store=PostgresOpportunityRepository(session),
            )
            try:
                await sync_council_members(
                    http,
                    PostgresCouncilRepository(session),
                    summary,
                    now=datetime.now(UTC),
                )
            except Exception as exc:  # letters fall back to stale members
                logger.exception("Council member sync failed")
                summary.errors.append(f"Ratsmitglieder: {type(exc).__name__}: {exc}")
            return summary
    finally:
        await completer.aclose()
        await database.close()


async def sync_council_members(
    http: PoliteHttpClient,
    repository: PostgresCouncilRepository,
    summary: IngestionSummary,
    *,
    now: datetime,
    body: OParlBody = oparl.DRESDEN,
) -> None:
    """Refreshes the members letters go to, at most once a week (a full
    OParl walk takes about ten minutes). Fraktionen without a known office
    address are reported on the admin page."""
    last = await repository.last_synced(body.source_id)
    if last is not None and now - last < MEMBER_SYNC_INTERVAL:
        return
    members = await fetch_council_members(http, body, today=now.date())
    await repository.replace(body.source_id, members, synced_at=now)
    summary.council_members = len(members)
    unknown = sorted(
        {
            m.fraktion_name or m.fraktion_url
            for m in members
            if m.fraktion_url and m.fraktion_url not in FRAKTION_OFFICES
        }
    )
    summary.errors.extend(f"Fraktion ohne Büro-Adresse: {name}" for name in unknown)
