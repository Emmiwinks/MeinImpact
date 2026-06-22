"""Ingestion pipeline orchestrator - runs Stages 0-9 once per invocation.

Stage 0: Topic Radar - DIP + NewsData.io -> ranked hot topics
Stage 1: Action Search per Topic - find best action per hot topic
Stages 2-9: Dedup, prefilter, enrich, classify, persist, deactivate, log.

Designed to be called daily by APScheduler (03:00 CET) or manually.
Creates its own DB connection and closes it on exit.
"""

import asyncio
import logging
import time
from datetime import UTC, datetime, timedelta
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
from meinimpact.infrastructure.sources.newsdata_client import (
    TOPIC_KEYWORDS,
    NewsDataClient,
)
from meinimpact.infrastructure.sources.protocol import RawSourceItem
from meinimpact.infrastructure.sources.tavily_client import TavilyClient

logger = logging.getLogger(__name__)

_TOPIC_URGENCY_THRESHOLD = 0.1
_LOOKBACK_DAYS_PARL = 14


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

        # ── Stage 0: Topic Radar ──────────────────────────────────────────────
        hot_topics = await _run_topic_radar(settings, existing["existing_urls"], errors)
        topics_above = [t for t, _ in hot_topics]
        logger.info(
            "Stage 0: %d/%d topics above threshold: %s",
            len(topics_above),
            len(TOPIC_KEYWORDS),
            topics_above,
        )

        # ── Stage 1: Action Search per Topic ─────────────────────────────────
        raw_items = await _search_actions_for_topics(
            hot_topics, existing["existing_urls"], settings, errors
        )
        logger.info("Stage 1: found %d candidate actions", len(raw_items))

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

        # -- Stages 6-9: Persist, deactivate, log --------------------------------
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
# Stage 0: Topic Radar
# ---------------------------------------------------------------------------


async def _run_topic_radar(
    settings: Settings,
    existing_urls: set[str],
    errors: list[str],
) -> list[tuple[str, float]]:
    """Returns topics sorted by urgency score, filtered to above-threshold only."""

    parl_counts = await _count_parliamentary_activity(settings, errors)
    news_counts = await _count_news_activity(settings, errors)

    max_parl = max(parl_counts.values(), default=1)
    max_news = max(news_counts.values(), default=1)

    scored: list[tuple[str, float]] = []
    for topic in TOPIC_KEYWORDS:
        norm_parl = parl_counts.get(topic, 0) / max(max_parl, 1)
        norm_news = news_counts.get(topic, 0) / max(max_news, 1)
        score = norm_parl * 0.6 + norm_news * 0.4
        logger.debug(
            "Topic radar: %s parl=%d news=%d score=%.3f",
            topic,
            parl_counts.get(topic, 0),
            news_counts.get(topic, 0),
            score,
        )
        if score >= _TOPIC_URGENCY_THRESHOLD:
            scored.append((topic, score))

    scored.sort(key=lambda x: x[1], reverse=True)
    return scored


async def _count_parliamentary_activity(
    settings: Settings,
    errors: list[str],
) -> dict[str, int]:
    """Counts recent DIP Vorgänge per topic using keyword matching on titles."""
    if not settings.dip_api_key:
        logger.warning("DIP API key not set — Stage 0 Signal A skipped")
        return {}

    since = datetime.now(UTC) - timedelta(days=_LOOKBACK_DAYS_PARL)
    try:
        adapter = DipAdapter(settings.dip_api_key)
        items = await adapter.fetch_new_items(since)
    except Exception as exc:
        msg = f"Stage 0 DIP fetch failed: {exc}"
        logger.error(msg)
        errors.append(msg)
        return {}

    counts: dict[str, int] = {t: 0 for t in TOPIC_KEYWORDS}
    for item in items:
        text_blob = (item["title"] + " " + item.get("description", "")).lower()  # type: ignore[misc]
        for topic, keywords in TOPIC_KEYWORDS.items():
            if any(kw.lower() in text_blob for kw in keywords):
                counts[topic] += 1
    return counts


async def _count_news_activity(
    settings: Settings,
    errors: list[str],
) -> dict[str, int]:
    """Counts recent NewsData.io articles per topic (Signal B)."""
    if not settings.newsdata_api_key:
        logger.info("MEINIMPACT_NEWSDATA_API_KEY not set — Stage 0 Signal B skipped")
        return {}
    try:
        client = NewsDataClient(settings.newsdata_api_key)
        return await client.count_articles_per_topic()
    except Exception as exc:
        msg = f"Stage 0 NewsData fetch failed: {exc}"
        logger.error(msg)
        errors.append(msg)
        return {}


# ---------------------------------------------------------------------------
# Stage 1: Action Search per Topic
# ---------------------------------------------------------------------------


async def _search_actions_for_topics(
    hot_topics: list[tuple[str, float]],
    existing_urls: set[str],
    settings: Settings,
    errors: list[str],
) -> list[RawSourceItem]:
    """Finds the best available action for each hot topic."""
    results: list[RawSourceItem] = []
    seen_urls: set[str] = set(existing_urls)

    for topic, score in hot_topics:
        keywords = TOPIC_KEYWORDS[topic]
        item = await _find_best_action(
            topic, keywords, score, seen_urls, settings, errors
        )
        if item:
            results.append(item)
            seen_urls.add(item["source_url"])

    return results


async def _find_best_action(
    topic: str,
    keywords: list[str],
    urgency_score: float,
    existing_urls: set[str],
    settings: Settings,
    errors: list[str],
) -> RawSourceItem | None:
    """Tries each priority in order and returns the first match not already in pool."""

    # Priority 1 & 2: DIP (Bundestag votes and petitions)
    if settings.dip_api_key:
        item = await _find_dip_action(
            topic, keywords, urgency_score, existing_urls, settings.dip_api_key, errors
        )
        if item:
            return item

    # Priority 3: Civil society petition via Tavily
    if settings.tavily_api_key:
        item = await _find_civil_petition(
            topic, keywords, existing_urls, settings.tavily_api_key, errors
        )
        if item:
            return item

    logger.debug("No action found for topic %r", topic)
    return None


async def _find_dip_action(
    topic: str,
    keywords: list[str],
    urgency_score: float,
    existing_urls: set[str],
    api_key: str,
    errors: list[str],
) -> RawSourceItem | None:
    """Searches DIP for votes or petitions relevant to this topic."""
    since = datetime.now(UTC) - timedelta(days=_LOOKBACK_DAYS_PARL)
    try:
        adapter = DipAdapter(api_key)
        items = await adapter.fetch_new_items(since)
    except Exception as exc:
        errors.append(f"DIP action search failed for {topic}: {exc}")
        return None

    kw_lower = [kw.lower() for kw in keywords]

    def matches(item: RawSourceItem) -> bool:
        blob = (item["title"] + " " + item.get("description", "")).lower()  # type: ignore[misc]
        return any(kw in blob for kw in kw_lower)

    def not_seen(item: RawSourceItem) -> bool:
        return item["source_url"] not in existing_urls

    relevant = [i for i in items if matches(i) and not_seen(i)]
    if not relevant:
        return None

    # Prefer petitions (P2) over regular Vorgänge (P1 fallback)
    petitions = [i for i in relevant if i["type"] == "petition"]
    return petitions[0] if petitions else relevant[0]


async def _find_civil_petition(
    topic: str,
    keywords: list[str],
    existing_urls: set[str],
    tavily_api_key: str,
    errors: list[str],
) -> RawSourceItem | None:
    """Searches Tavily for civil society petitions on WeAct or openPetition."""
    query = f"{' OR '.join(keywords[:3])} Petition unterzeichnen"
    try:
        tavily = TavilyClient(tavily_api_key)
        results = await tavily.search(
            query,
            max_results=3,
            days=30,
            include_domains=["weact.campact.de", "openpetition.de"],
        )
        for r in results:
            url = str(r.get("url") or "")
            if url and url not in existing_urls:
                title = str(r.get("title") or "")
                content = str(r.get("content") or "")
                external_id = url.rstrip("/").split("/")[-1] or url[-40:]
                return RawSourceItem(
                    external_id=external_id,
                    title=title,
                    type="petition",
                    status="offen",
                    deadline=None,
                    source_url=url,
                    description=content[:500],
                    initiated_by="Zivilgesellschaft",
                    source="tavily_petition_search",
                )
    except Exception as exc:
        errors.append(f"Tavily petition search failed for {topic}: {exc}")
    return None


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
    return ClassifiedAction(
        **item,  # type: ignore[misc]
        topics=[],
        urgency="low",
        werte_relevanz={},
        pro_argumente=[],
        contra_argumente=[],
        action_types=[],
        is_controversial=False,
        position_required=False,
        momentum_score=calculate_momentum(0),
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
        record = {
            "id": str(uuid4()),
            "title": item["title"],
            "action_type": domain_type,
            "summary": item.get("description", item["title"])[:500],
            "topics": item.get("topics", []),
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
            "momentum_score": item.get("momentum_score", 0.3),
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
