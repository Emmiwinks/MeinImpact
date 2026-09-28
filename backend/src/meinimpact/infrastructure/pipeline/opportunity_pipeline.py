"""Opportunity ingestion pipeline — trigger-based, not scheduled.

Composes three reusable, independently-testable components
(`TavilyOpportunityAdapter`, `OpportunityExtractor`,
`MistralEmbeddingClient`) with the repository's dedup-aware upsert. No
in-process scheduler — this runs only when explicitly triggered (the admin
route, or a future external cron hitting it), per the project's "trigger-
based, not scheduled" requirement. See specs/data/ingestion-pipeline.md
"Status" and project memory `project_dip_to_tavily_pivot.md` /
`project_tavily_retrieval_calibration.md` for how this design was reached.

Extraction+embedding run concurrently per item (network-bound, no shared
state), but persistence runs sequentially afterward — `AsyncSession` isn't
safe for concurrent use, and each repository call commits its own
transaction.
"""

import asyncio
from dataclasses import dataclass, field
from uuid import UUID, uuid4

from meinimpact.infrastructure.ai.embeddings import MistralEmbeddingClient
from meinimpact.infrastructure.ai.opportunity_extractor import (
    ExtractedOpportunity,
    OpportunityExtractor,
)
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
    UpsertOutcome,
)
from meinimpact.infrastructure.sources.tavily_opportunity_adapter import (
    REGIONS,
    RawOpportunityItem,
    TavilyOpportunityAdapter,
)

_MAX_CONCURRENCY = 5

_ExtractedItem = tuple[RawOpportunityItem, ExtractedOpportunity, list[float]]


@dataclass
class IngestionSummary:
    """Live counts for one trigger-based run — not persisted (the old
    `pipeline_runs` log table was dropped with the DIP-sourced pipeline;
    re-add a run-log table later if monitoring actually needs history)."""

    fetched: int = 0
    actionable: int = 0
    inserted: int = 0
    refreshed: int = 0
    errors: list[str] = field(default_factory=list)
    run_id: UUID = field(default_factory=uuid4)


async def run_ingestion(
    *,
    source: TavilyOpportunityAdapter,
    extractor: OpportunityExtractor,
    embedder: MistralEmbeddingClient,
    repository: PostgresOpportunityRepository,
    regions: list[str] | None = None,
) -> IngestionSummary:
    """Runs fetch -> extract -> embed -> upsert for each region in turn.

    Generates one `run_id` for the whole call, stamped on every row this
    run touches (insert or refresh) — that's what lets the pool endpoint
    later identify "everything from the latest run" as one set. See
    `PostgresOpportunityRepository.list_current_run`.
    """
    summary = IngestionSummary()
    run_id = summary.run_id
    semaphore = asyncio.Semaphore(_MAX_CONCURRENCY)

    for region in regions or list(REGIONS):
        items = await source.fetch(region)
        summary.fetched += len(items)

        extracted_items = await asyncio.gather(
            *[
                _extract_and_embed(item, extractor, embedder, semaphore, summary.errors)
                for item in items
            ]
        )

        for extracted_item in extracted_items:
            if extracted_item is None:
                continue
            item, extracted, embedding = extracted_item
            summary.actionable += 1
            try:
                outcome = await repository.upsert(
                    extracted=extracted,
                    embedding=embedding,
                    source_org=item["source_org"],
                    source_url=item["url"],
                    region=item["region"],
                    run_id=run_id,
                )
            except Exception as exc:
                summary.errors.append(f"persist failed for {item['url']}: {exc}")
                continue
            if outcome is UpsertOutcome.INSERTED:
                summary.inserted += 1
            else:
                summary.refreshed += 1

    return summary


async def _extract_and_embed(
    item: RawOpportunityItem,
    extractor: OpportunityExtractor,
    embedder: MistralEmbeddingClient,
    semaphore: asyncio.Semaphore,
    errors: list[str],
) -> _ExtractedItem | None:
    async with semaphore:
        try:
            extracted = await extractor.extract(item)
            if extracted is None:
                return None
            embedding = await embedder.embed(extracted["decision_object"])
            return (item, extracted, embedding)
        except Exception as exc:
            errors.append(f"extraction failed for {item['url']}: {exc}")
            return None
