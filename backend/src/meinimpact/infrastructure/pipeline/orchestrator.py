"""Ingestion pipeline orchestrator — composition root for the two parallel
pipelines described in specs/data/ingestion-pipeline.md.

Runs Pipeline 1 (parliamentary, top-down) and Pipeline 2 (petition,
bottom-up) concurrently via `asyncio.gather`, merges and deduplicates their
outputs, persists the survivors, deactivates expired actions, and logs the
run. All fetch/state-determination/classification logic lives in the two
pipeline modules and their steps — this file only composes them.

Designed to be called daily by APScheduler (03:00 CET, see `main.py`) or
manually.
"""

import asyncio
import logging
import time
from collections import Counter
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncSession

from meinimpact.core.config import Settings
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.models import CivicActionRecord, PipelineRunRecord
from meinimpact.infrastructure.pipeline.merge import merge_and_deduplicate
from meinimpact.infrastructure.pipeline.parliamentary_pipeline import (
    run_parliamentary_pipeline,
)
from meinimpact.infrastructure.pipeline.petition_pipeline import run_petition_pipeline
from meinimpact.infrastructure.pipeline.stages import (
    effort_minutes_for,
    impact_hint_for,
    map_domain_action_type,
)
from meinimpact.infrastructure.pipeline.step import ItemState, PipelineDeps
from meinimpact.infrastructure.pipeline.steps.build_rule_context import (
    PreviousSignatureLookup,
)
from meinimpact.infrastructure.pipeline.steps.trace_discards import DiscardSink
from meinimpact.infrastructure.sources.protocol import RawSourceItem

logger = logging.getLogger(__name__)


async def run_ingestion_pipeline(settings: Settings) -> None:
    """Executes the full ingestion pipeline end-to-end."""
    run_id = uuid4()
    start = time.monotonic()
    errors: list[str] = []
    deps = PipelineDeps(settings=settings, run_id=run_id, errors=errors)

    logger.info("Pipeline run %s starting", run_id)

    db = Database(settings.database_url)
    try:
        async with db.engine.connect() as conn:
            existing_urls, existing_titles = await _load_existing(conn)

        discarded_ids: list[str] = []

        async def _record_discard(item: ItemState) -> None:
            discarded_ids.append(item.raw.get("external_id", ""))

        previous_signature_counts = await _load_previous_signature_counts(db)

        def _previous_signature_lookup(item: RawSourceItem) -> int | None:
            return previous_signature_counts.get(item.get("source_url", ""))

        # Stage 0a/0b: both pipelines run concurrently — they use different
        # sources and share no mutable state until merge.
        parliamentary_items, petition_items = await _run_both_pipelines(
            deps, _record_discard, _previous_signature_lookup
        )
        logger.info(
            "Pipelines complete: %d parliamentary, %d petition, %d discarded (state D)",
            len(parliamentary_items),
            len(petition_items),
            len(discarded_ids),
        )

        # Stage 1: Merge + Deduplicate
        merged = merge_and_deduplicate(
            parliamentary_items,
            petition_items,
            existing_urls,
            existing_titles,
        )
        state_counts = _count_states(merged)

        # Stage 3/4/6/7: Persist, deactivate, log
        inserted = 0
        async with db._session_factory() as session:
            inserted = await _persist(merged, session)
            await _deactivate_expired(session)
            await _log_run(
                session,
                run_id=run_id,
                parliamentary_actions_found=len(parliamentary_items),
                petition_actions_found=len(petition_items),
                state_counts=state_counts,
                state_d_discarded=len(discarded_ids),
                inserted=inserted,
                errors=errors,
                duration=time.monotonic() - start,
            )
            await session.commit()

        logger.info(
            "Pipeline run %s complete: %d inserted in %.1fs",
            run_id,
            inserted,
            time.monotonic() - start,
        )

    except Exception as exc:
        logger.critical(
            "Pipeline run %s ABORTED — nothing persisted: %s", run_id, exc, exc_info=True
        )
        errors.append(str(exc))
    finally:
        await db.close()


async def _run_both_pipelines(
    deps: PipelineDeps,
    discard_sink: DiscardSink,
    previous_signature_lookup: PreviousSignatureLookup,
) -> tuple[list[ItemState], list[ItemState]]:
    """Runs both pipelines concurrently. Plain `asyncio.gather` (no
    `return_exceptions`) — a failure in either pipeline propagates
    immediately and cancels the other, so `run_ingestion_pipeline`'s outer
    handler aborts the whole run and persists nothing, rather than
    silently treating a broken source as "found no items"."""
    return await asyncio.gather(
        run_parliamentary_pipeline(deps, discard_sink),
        run_petition_pipeline(deps, discard_sink, previous_signature_lookup),
    )


def _count_states(items: list[ItemState]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for item in items:
        if item.state_trace is not None:
            counts[item.state_trace.engagement_state] += 1
    return counts


# ---------------------------------------------------------------------------
# Existing-pool lookups
# ---------------------------------------------------------------------------


async def _load_existing(conn: AsyncConnection) -> tuple[set[str], list[str]]:
    result = await conn.execute(
        text("SELECT source_url, title FROM civic_actions WHERE active = true")
    )
    rows = result.fetchall()
    existing_urls = {row[0] for row in rows}
    existing_titles = [row[1] for row in rows]
    return existing_urls, existing_titles


async def _load_previous_signature_counts(db: Database) -> dict[str, int]:
    """Loads `previous_signature_count` per `source_url`, so the petition
    pipeline's momentum rule can compare against last run's count."""
    async with db.engine.connect() as conn:
        result = await conn.execute(
            text(
                "SELECT source_url, previous_signature_count FROM civic_actions "
                "WHERE previous_signature_count IS NOT NULL"
            )
        )
        return {row[0]: row[1] for row in result.fetchall()}


# ---------------------------------------------------------------------------
# Persist
# ---------------------------------------------------------------------------


async def _persist(items: list[ItemState], session: AsyncSession) -> int:
    inserted = 0
    for item in items:
        classified = item.classified
        if classified is None:
            continue
        trace = item.state_trace
        engagement_state = trace.engagement_state if trace is not None else "C"
        state_reason = trace.state_reason if trace is not None else None
        domain_type = map_domain_action_type(classified)
        urgency = classified.get("urgency", "low")

        record = {
            "id": str(uuid4()),
            "title": classified["title"],
            "action_type": domain_type,
            "summary": classified.get("description", classified["title"])[:500],
            "region": None,
            "deadline": classified.get("deadline"),
            "effort_minutes": effort_minutes_for(domain_type),
            "impact_hint": impact_hint_for(str(urgency)),
            "source_url": classified["source_url"],
            "urgency": str(urgency),
            "werte_relevanz": classified.get("werte_relevanz", {}),
            "external_id": classified.get("external_id"),
            "pro_argumente": classified.get("pro_argumente", []),
            "contra_argumente": classified.get("contra_argumente", []),
            "action_types": classified.get("action_types", []),
            "is_controversial": classified.get("is_controversial", False),
            "position_required": classified.get("position_required", False),
            "tavily_context": classified.get("tavily_context"),
            "engagement_state": engagement_state,
            "state_reason": state_reason,
            "pipeline_source": item.pipeline_source or "parliamentary",
            "previous_signature_count": item.raw.get("signature_count"),
            "active": True,
            "updated_at": datetime.now(UTC),
        }
        stmt = pg_insert(CivicActionRecord).values(**record)
        stmt = stmt.on_conflict_do_update(
            index_elements=["source_url"],
            set_={
                "urgency": stmt.excluded.urgency,
                "engagement_state": stmt.excluded.engagement_state,
                "state_reason": stmt.excluded.state_reason,
                "previous_signature_count": stmt.excluded.previous_signature_count,
                "tavily_context": stmt.excluded.tavily_context,
                "updated_at": stmt.excluded.updated_at,
            },
        )
        await session.execute(stmt)
        inserted += 1
    return inserted


# ---------------------------------------------------------------------------
# Deactivate expired
# ---------------------------------------------------------------------------


async def _deactivate_expired(session: AsyncSession) -> None:
    await session.execute(
        update(CivicActionRecord)
        .where(
            CivicActionRecord.deadline.isnot(None),
            CivicActionRecord.deadline < text("now() - INTERVAL '7 days'"),
            CivicActionRecord.active.is_(True),
        )
        .values(active=False)
    )


# ---------------------------------------------------------------------------
# Log run
# ---------------------------------------------------------------------------


async def _log_run(
    session: AsyncSession,
    *,
    run_id: UUID,
    parliamentary_actions_found: int,
    petition_actions_found: int,
    state_counts: Counter[str],
    state_d_discarded: int,
    inserted: int,
    errors: list[str],
    duration: float,
) -> None:
    record = PipelineRunRecord(
        id=run_id,
        parliamentary_actions_found=parliamentary_actions_found,
        petition_actions_found=petition_actions_found,
        state_a_count=state_counts.get("A", 0),
        state_b_count=state_counts.get("B", 0),
        state_c_count=state_counts.get("C", 0),
        state_d_discarded=state_d_discarded,
        inserted_count=inserted,
        errors=errors,
        duration_seconds=duration,
    )
    session.add(record)
