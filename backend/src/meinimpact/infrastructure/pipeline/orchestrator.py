"""Ingestion pipeline orchestrator - runs Stages 0-9 once per invocation.

Stage 0: Hotness Evaluation - DIP beratungsstand-based fetch → imminent items
Stage 1: Civil Society Petitions - Tavily broad petition search
Stages 2-9: Dedup, prefilter, enrich (skipped), classify, persist, deactivate, log.

No topic taxonomy. Hotness is determined by parliamentary process stage
(beratungsstand) and recency, not keyword matching against predefined categories.

Designed to be called daily by APScheduler (03:00 CET) or manually.
"""

import asyncio
import logging
import time
from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.core.config import Settings
from meinimpact.infrastructure.ai.classifier import MistralClassifier
from meinimpact.infrastructure.database import Database
from meinimpact.infrastructure.models import CivicActionRecord, PipelineRunRecord
from meinimpact.infrastructure.pipeline.stages import (
    calculate_momentum,
    deduplicate,
    effort_minutes_for,
    impact_hint_for,
    map_domain_action_type,
    prefilter,
)
from meinimpact.infrastructure.pipeline.types import ClassifiedAction
from meinimpact.infrastructure.sources.dip_adapter import DipAdapter
from meinimpact.infrastructure.sources.protocol import RawSourceItem
from meinimpact.infrastructure.sources.tavily_client import TavilyClient

logger = logging.getLogger(__name__)


async def run_ingestion_pipeline(settings: Settings) -> None:
    """Executes the full ingestion pipeline end-to-end."""
    run_id = uuid4()
    start = time.monotonic()
    errors: list[str] = []

    logger.info("Pipeline run %s starting", run_id)

    db = Database(settings.database_url)
    try:
        async with db.engine.connect() as conn:
            existing = await _load_existing(conn)

        # ── Stage 0: Hotness Evaluation (DIP beratungsstand) ─────────────────
        dip_items = await _fetch_hot_dip_items(settings, errors)
        logger.info("Stage 0: %d hot DIP items", len(dip_items))

        # ── Stage 1: Civil Society Petitions (Tavily) ─────────────────────────
        petition_items = await _fetch_civil_petitions(settings, errors)
        logger.info("Stage 1: %d civil society petitions", len(petition_items))

        raw_items = dip_items + petition_items

        # ── Stage 2: Deduplicate ──────────────────────────────────────────────
        new_items = deduplicate(raw_items, **existing)
        logger.info(
            "Stage 2: %d new after dedup (dropped %d)",
            len(new_items),
            len(raw_items) - len(new_items),
        )

        # ── Stage 3: Prefilter ────────────────────────────────────────────────
        filtered = prefilter(new_items)
        logger.info(
            "Stage 3: %d pass prefilter (dropped %d)",
            len(filtered),
            len(new_items) - len(filtered),
        )

        # ── Stage 4: Tavily enrichment — SKIPPED in MVP ───────────────────────
        logger.info("Stage 4: skipped (MVP)")

        # ── Stage 5: Classify ─────────────────────────────────────────────────
        classified = await _classify_all(filtered, settings, errors)
        classified_count = sum(1 for c in classified if c is not None)
        logger.info("Stage 5: %d classified", classified_count)

        # ── Stages 6-9: Persist, deactivate, log ─────────────────────────────
        inserted = 0
        async with db._session_factory() as session:
            inserted = await _persist(classified, session)
            await _deactivate_expired(session)
            await _log_run(
                session,
                run_id=run_id,
                fetched=len(raw_items),
                deduplicated=len(new_items),
                prefiltered=len(filtered),
                classified=classified_count,
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
        logger.exception("Pipeline run %s failed: %s", run_id, exc)
        errors.append(str(exc))
    finally:
        await db.close()


# ---------------------------------------------------------------------------
# Stage 0: Hotness Evaluation
# ---------------------------------------------------------------------------


async def _fetch_hot_dip_items(
    settings: Settings,
    errors: list[str],
) -> list[RawSourceItem]:
    """Fetches DIP Vorgänge in active beratungsstand stages."""
    if not settings.dip_api_key:
        logger.warning("DIP API key not set — Stage 0 skipped")
        return []
    try:
        adapter = DipAdapter(settings.dip_api_key)
        return await adapter.fetch_hot_items()
    except Exception as exc:
        msg = f"Stage 0 DIP fetch failed: {exc}"
        logger.error(msg)
        errors.append(msg)
        return []


# ---------------------------------------------------------------------------
# Stage 1: Civil Society Petitions
# ---------------------------------------------------------------------------


_PETITION_DOMAINS = {"weact.campact.de", "openpetition.de"}
# Tavily's include_domains is not guaranteed strict — validate in Python.
# A valid petition URL must also contain one of these path segments (not a listing page).
_PETITION_PATH_MARKERS = {"/petition/", "/p/"}


def _is_valid_petition_url(url: str) -> bool:
    from urllib.parse import urlparse
    parsed = urlparse(url)
    host = parsed.netloc.lower().removeprefix("www.")
    if host not in _PETITION_DOMAINS:
        return False
    path = parsed.path
    # openpetition.de/at/ is the Austrian content section — exclude it
    if path.startswith("/at/"):
        return False
    # /petition/blog/ URLs are update pages, not the petition itself
    if "/petition/blog" in path:
        return False
    return any(marker in path for marker in _PETITION_PATH_MARKERS)


async def _fetch_civil_petitions(
    settings: Settings,
    errors: list[str],
) -> list[RawSourceItem]:
    """Broad Tavily search for active civil society petitions."""
    if not settings.tavily_api_key:
        logger.info("MEINIMPACT_TAVILY_API_KEY not set — Stage 1 skipped")
        return []
    try:
        tavily = TavilyClient(settings.tavily_api_key)
        results = await tavily.search(
            "Petition Politik Bundestag unterzeichnen 2026",
            max_results=15,
            days=14,
            include_domains=list(_PETITION_DOMAINS),
        )
        items: list[RawSourceItem] = []
        for r in results:
            url = str(r.get("url") or "")
            if not url or not _is_valid_petition_url(url):
                logger.debug("Stage 1: skipping non-petition URL %s", url)
                continue
            title = str(r.get("title") or "")
            content = str(r.get("content") or "")
            external_id = url.rstrip("/").split("/")[-1] or url[-40:]
            items.append(
                RawSourceItem(
                    external_id=external_id,
                    title=title,
                    type="petition",
                    status="offen",
                    deadline=None,
                    source_url=url,
                    description=content[:500],
                    initiated_by="Zivilgesellschaft",
                    source="tavily_petition_search",
                    imminence_score=0.3,
                )
            )
        return items
    except Exception as exc:
        msg = f"Stage 1 Tavily petition search failed: {exc}"
        logger.error(msg)
        errors.append(msg)
        return []


# ---------------------------------------------------------------------------
# Stage 2 helper — load existing URLs and titles from DB
# ---------------------------------------------------------------------------


async def _load_existing(conn: object) -> dict[str, object]:
    result = await conn.execute(  # type: ignore[union-attr]
        text("SELECT source_url, title FROM civic_actions WHERE active = true")
    )
    rows = result.fetchall()
    return {
        "existing_urls": {row[0] for row in rows},
        "existing_titles": [row[1] for row in rows],
    }


# ---------------------------------------------------------------------------
# Stage 5: Classification
# ---------------------------------------------------------------------------


async def _classify_all(
    items: list[RawSourceItem],
    settings: Settings,
    errors: list[str],
) -> list[ClassifiedAction | None]:
    if not settings.mistral_api_key:
        logger.warning(
            "MEINIMPACT_MISTRAL_API_KEY not set — inserting without classification"
        )
        return [_default_classified(item) for item in items]

    classifier = MistralClassifier(
        api_key=settings.mistral_api_key,
        base_url=settings.mistral_base_url,
        model=settings.mistral_model,
    )
    results = await asyncio.gather(
        *[classifier.classify(item) for item in items],
        return_exceptions=True,
    )
    classified: list[ClassifiedAction | None] = []
    for result in results:
        if isinstance(result, Exception):
            errors.append(f"Classification error: {result}")
            classified.append(None)
        else:
            classified.append(result)  # type: ignore[arg-type]
    return classified


def _default_classified(item: RawSourceItem) -> ClassifiedAction:
    imminence = item.get("imminence_score", 0.3)  # type: ignore[misc]
    return ClassifiedAction(
        **item,  # type: ignore[misc]
        urgency="low",
        werte_relevanz={},
        pro_argumente=[],
        contra_argumente=[],
        action_types=[],
        is_controversial=False,
        position_required=False,
        momentum_score=calculate_momentum(imminence),
    )


# ---------------------------------------------------------------------------
# Stage 6: Persist
# ---------------------------------------------------------------------------


async def _persist(
    items: list[ClassifiedAction | None],
    session: AsyncSession,
) -> int:
    inserted = 0
    for item in items:
        if item is None:
            continue
        domain_type = map_domain_action_type(item)
        urgency = item.get("urgency", "low")
        imminence = item.get("imminence_score", 0.3)  # type: ignore[misc]
        momentum = calculate_momentum(imminence)

        record = {
            "id": str(uuid4()),
            "title": item["title"],
            "action_type": domain_type,
            "summary": item.get("description", item["title"])[:500],
            "region": None,
            "deadline": item.get("deadline"),
            "effort_minutes": effort_minutes_for(domain_type),
            "impact_hint": impact_hint_for(str(urgency)),
            "source_url": item["source_url"],
            "urgency": str(urgency),
            "werte_relevanz": item.get("werte_relevanz", {}),
            "external_id": item.get("external_id"),
            "pro_argumente": item.get("pro_argumente", []),
            "contra_argumente": item.get("contra_argumente", []),
            "action_types": item.get("action_types", []),
            "is_controversial": item.get("is_controversial", False),
            "position_required": item.get("position_required", False),
            "tavily_context": item.get("tavily_context"),
            "momentum_score": momentum,
            "active": True,
            "updated_at": datetime.now(UTC),
        }
        stmt = pg_insert(CivicActionRecord).values(**record)
        stmt = stmt.on_conflict_do_update(
            index_elements=["source_url"],
            set_={
                "urgency": stmt.excluded.urgency,
                "momentum_score": stmt.excluded.momentum_score,
                "tavily_context": stmt.excluded.tavily_context,
                "updated_at": stmt.excluded.updated_at,
            },
        )
        await session.execute(stmt)
        inserted += 1
    return inserted


# ---------------------------------------------------------------------------
# Stage 7: Deactivate expired
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
# Stage 9: Log run
# ---------------------------------------------------------------------------


async def _log_run(
    session: AsyncSession,
    *,
    run_id: object,
    fetched: int,
    deduplicated: int,
    prefiltered: int,
    classified: int,
    inserted: int,
    errors: list[str],
    duration: float,
) -> None:
    record = PipelineRunRecord(
        id=run_id,  # type: ignore[arg-type]
        fetched_count=fetched,
        deduplicated_count=deduplicated,
        prefiltered_count=prefiltered,
        classified_count=classified,
        inserted_count=inserted,
        errors=errors,
        duration_seconds=duration,
    )
    session.add(record)
