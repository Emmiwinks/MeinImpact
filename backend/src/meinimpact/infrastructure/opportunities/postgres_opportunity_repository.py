"""PostgreSQL-backed opportunity repository — dedup-aware upsert, plus the
"one run, one feed" read side.

Write side: two-step de-duplication per the rebuild plan section 4: exact
`source_url` match first (cheap, catches literal re-fetches of the same
page), then embedding cosine-similarity against `decision_object` for
genuinely new URLs (catches the same real-world thing described
differently by two sources). No adjudication tier, no confidence scoring —
a single threshold.

`DEDUP_DISTANCE_THRESHOLD` is NOT YET CALIBRATED against real duplicate
vs. distinct pairs (rebuild plan section 9) — it's a reasonable starting
point pending that hand-labeled validation, not a settled constant.

Read side: `list_current_run()` serves only the most recent ingestion
run's opportunities — rediscovery-by-search-ranking isn't a real hotness
signal (see project memory `project_dip_to_tavily_pivot.md`), so the feed
is always exactly "what the latest run found," not an accumulating pool.
Older runs' rows stay in the table for de-duplication but are never
served.
"""

import uuid
from datetime import UTC, datetime
from enum import StrEnum

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.domain.entities import Opportunity
from meinimpact.infrastructure.ai.opportunity_extractor import ExtractedOpportunity
from meinimpact.infrastructure.models import OpportunityRecord

# Cosine distance (0 = identical, 2 = opposite) below which two
# opportunities are treated as duplicates — roughly 0.90 cosine similarity.
DEDUP_DISTANCE_THRESHOLD = 0.10


class UpsertOutcome(StrEnum):
    INSERTED = "inserted"
    REFRESHED = "refreshed"


class PostgresOpportunityRepository:
    """Persists extracted opportunities, merging into an existing row when
    one is found rather than always inserting, and serves the current
    run's opportunities for the pool endpoint."""

    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def upsert(
        self,
        *,
        extracted: ExtractedOpportunity,
        embedding: list[float],
        source_org: str,
        source_url: str,
        region: str,
        run_id: uuid.UUID,
    ) -> UpsertOutcome:
        """Inserts a new opportunity, or refreshes an existing match's
        `support_count`/`deadline` in place. Never touches `retrieved_at`
        on a refresh (first-seen timestamp, kept for reference — no longer
        the feed's sort key, see `list_current_run`). Always stamps
        `last_seen_run_id = run_id`, insert or refresh — that's what makes
        this row part of "the current feed" until a later run supersedes
        it."""
        existing = await self._find_by_url(source_url)
        if existing is None:
            existing = await self._find_similar(embedding)

        if existing is not None:
            self._refresh(existing, extracted, run_id)
            await self._session.commit()
            return UpsertOutcome.REFRESHED

        self._session.add(
            OpportunityRecord(
                source_org=source_org,
                decision_object=extracted["decision_object"],
                plain_language_title=extracted["plain_language_title"],
                plain_language_summary=extracted["plain_language_summary"],
                affected_tags=extracted["affected_tags"],
                region=region,
                werte_relevanz=extracted["werte_relevanz"],
                deadline=extracted["deadline"],
                support_count=extracted["support_count"],
                support_count_as_of=extracted["support_count_as_of"],
                content_published_at=extracted["content_published_at"],
                source_url=source_url,
                action_types=extracted["action_types"],
                pro_argumente=extracted["pro_argumente"],
                contra_argumente=extracted["contra_argumente"],
                personal_impact_snippets=extracted["personal_impact_snippets"],
                embedding=embedding,
                last_seen_run_id=run_id,
            )
        )
        await self._session.commit()
        return UpsertOutcome.INSERTED

    async def list_current_run(self) -> list[Opportunity]:
        """Returns the opportunities touched by the most recent ingestion
        run only. Empty list when no run has ever happened."""
        latest_run = await self._session.execute(
            select(OpportunityRecord.last_seen_run_id)
            .where(OpportunityRecord.active == True)  # noqa: E712
            .order_by(OpportunityRecord.updated_at.desc())
            .limit(1)
        )
        run_id = latest_run.scalar_one_or_none()
        if run_id is None:
            return []

        result = await self._session.execute(
            select(OpportunityRecord).where(
                OpportunityRecord.active == True,  # noqa: E712
                OpportunityRecord.last_seen_run_id == run_id,
            )
        )
        return [_to_domain(r) for r in result.scalars().all()]

    async def _find_by_url(self, source_url: str) -> OpportunityRecord | None:
        result = await self._session.execute(
            select(OpportunityRecord).where(
                OpportunityRecord.source_url == source_url,
                OpportunityRecord.active == True,  # noqa: E712
            )
        )
        return result.scalar_one_or_none()

    async def _find_similar(self, embedding: list[float]) -> OpportunityRecord | None:
        distance = OpportunityRecord.embedding.cosine_distance(embedding)
        result = await self._session.execute(
            select(OpportunityRecord)
            .where(
                OpportunityRecord.active == True,  # noqa: E712
                distance <= DEDUP_DISTANCE_THRESHOLD,
            )
            .order_by(distance)
            .limit(1)
        )
        return result.scalars().first()

    def _refresh(
        self,
        existing: OpportunityRecord,
        extracted: ExtractedOpportunity,
        run_id: uuid.UUID,
    ) -> None:
        """Only overwrites fields this run actually found something for —
        a run that couldn't extract a support_count shouldn't erase a
        previously-known one."""
        if extracted["support_count"] is not None:
            existing.support_count = extracted["support_count"]
            existing.support_count_as_of = extracted["support_count_as_of"]
        if extracted["deadline"] is not None:
            existing.deadline = extracted["deadline"]
        existing.last_seen_run_id = run_id
        existing.updated_at = datetime.now(UTC)


def _to_domain(record: OpportunityRecord) -> Opportunity:
    return Opportunity(
        id=record.id,
        source_org=record.source_org,
        decision_object=record.decision_object,
        plain_language_title=record.plain_language_title,
        plain_language_summary=record.plain_language_summary,
        affected_tags=tuple(record.affected_tags or []),
        region=record.region,
        werte_relevanz=dict(record.werte_relevanz or {}),
        deadline=record.deadline,
        support_count=record.support_count,
        support_count_as_of=record.support_count_as_of,
        content_published_at=record.content_published_at,
        retrieved_at=record.retrieved_at,
        source_url=record.source_url,
        action_types=tuple(record.action_types or []),
        pro_argumente=tuple(record.pro_argumente or []),
        contra_argumente=tuple(record.contra_argumente or []),
        personal_impact_snippets=dict(record.personal_impact_snippets or {}),
    )
