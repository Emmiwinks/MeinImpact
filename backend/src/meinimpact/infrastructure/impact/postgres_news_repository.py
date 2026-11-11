"""News about tracked opportunities in Postgres.

Every relevant hit of every ladder run is kept with its rung; what the app
shows is decided when reading (`ImpactNews.shown`), the same rule as
`LadderResult.items`, applied across all runs. The spend of the scheduled
search is recorded in `api_spend` under one endpoint name, so the daily
budget holds across rounds, restarts and machines.
"""

import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from email.utils import parsedate_to_datetime

from sqlalchemy import ColumnElement, func, or_, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.impact.news_ladder import (
    BACKGROUND,
    ImpactSubject,
    LadderResult,
    search_since,
)
from meinimpact.infrastructure.models import (
    ApiSpendRecord,
    OpportunityNewsRecord,
    OpportunityRecord,
)

SPEND_ENDPOINT = "impact_news"

_SNIPPET_CHARS = 600
_SUMMARY_CHARS = 800


@dataclass(frozen=True, slots=True)
class ImpactNewsItem:
    level: str
    kind: str
    url: str
    title: str
    snippet: str
    published_on: date | None
    found_at: datetime


@dataclass(frozen=True, slots=True)
class ImpactNews:
    # None: never searched yet
    checked_at: datetime | None
    # Newest first
    items: tuple[ImpactNewsItem, ...]

    @property
    def shown(self) -> tuple[ImpactNewsItem, ...]:
        """Every specific item, else at most one background item."""
        specific = tuple(i for i in self.items if i.level != BACKGROUND)
        return specific or tuple(i for i in self.items if i.level == BACKGROUND)[:1]


@dataclass(frozen=True, slots=True)
class ClaimedSearch:
    opportunity_id: uuid.UUID
    subject: ImpactSubject
    # To give the claim back if the search fails
    previous_checked_at: datetime | None


class PostgresImpactNewsRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def commit(self) -> None:
        await self._session.commit()

    async def claim_due(
        self, *, now: datetime, checked_before: datetime
    ) -> ClaimedSearch | None:
        """Takes the tracked opportunity that waited longest (never searched
        first) and marks it checked now, committed, so another machine skips
        it. None when no opportunity is due."""
        record = await self._session.scalar(
            select(OpportunityRecord)
            .where(
                OpportunityRecord.tracked_since.is_not(None),
                OpportunityRecord.is_relevant.is_(True),
                or_(
                    OpportunityRecord.news_checked_at.is_(None),
                    OpportunityRecord.news_checked_at < checked_before,
                ),
            )
            .order_by(OpportunityRecord.news_checked_at.asc().nulls_first())
            .limit(1)
            .with_for_update(skip_locked=True)
        )
        if record is None:
            return None
        previous = record.news_checked_at
        record.news_checked_at = now
        await self._session.commit()
        return ClaimedSearch(
            opportunity_id=record.id,
            subject=ImpactSubject(
                kind=record.kind,
                title=record.registry_title,
                summary=(record.registry_summary or record.summary or "")[
                    :_SUMMARY_CHARS
                ],
                organizer=record.organizer,
                locality=record.locality,
                source_url=record.source_url,
                since=search_since(record.opens_on, record.first_seen_at.date()),
            ),
            previous_checked_at=previous,
        )

    async def release(self, claim: ClaimedSearch) -> None:
        """Gives a claim back after a failed search, so it is due again."""
        await self._session.execute(
            update(OpportunityRecord)
            .where(OpportunityRecord.id == claim.opportunity_id)
            .values(news_checked_at=claim.previous_checked_at)
        )
        await self._session.commit()

    async def save(
        self, opportunity_id: uuid.UUID, result: LadderResult, *, checked_at: datetime
    ) -> int:
        """Stores the run's relevant hits not stored yet and marks the
        opportunity checked. Returns the number of new hits."""
        rows = [
            {
                "opportunity_id": opportunity_id,
                "level": rung.level,
                "kind": judged.kind,
                "url": judged.hit.url,
                "title": judged.hit.title,
                "snippet": judged.hit.content[:_SNIPPET_CHARS],
                "published_on": parse_published(judged.hit.published_date),
                "reason": judged.reason,
                "found_at": checked_at,
            }
            for rung in result.rungs
            for judged in rung.relevant
        ]
        added = 0
        if rows:
            inserted = await self._session.execute(
                insert(OpportunityNewsRecord)
                .values(rows)
                .on_conflict_do_nothing(constraint="uq_opportunity_news_url")
                .returning(OpportunityNewsRecord.id)
            )
            added = len(inserted.all())
        await self._session.execute(
            update(OpportunityRecord)
            .where(OpportunityRecord.id == opportunity_id)
            .values(news_checked_at=checked_at)
        )
        await self._session.flush()
        return added

    async def spent_on(self, day: date) -> Decimal:
        total = await self._session.scalar(
            select(func.coalesce(func.sum(ApiSpendRecord.cost_eur), 0)).where(
                ApiSpendRecord.date == day,
                ApiSpendRecord.endpoint == SPEND_ENDPOINT,
            )
        )
        return Decimal(total or 0)

    def record_spend(
        self, day: date, provider: str, cost_eur: Decimal, *, tokens: int | None
    ) -> None:
        self._session.add(
            ApiSpendRecord(
                date=day,
                provider=provider,
                endpoint=SPEND_ENDPOINT,
                tokens_used=tokens,
                cost_eur=cost_eur,
            )
        )

    async def news_for(self, opportunity_id: uuid.UUID) -> ImpactNews:
        checked_at = await self._session.scalar(
            select(OpportunityRecord.news_checked_at).where(
                OpportunityRecord.id == opportunity_id
            )
        )
        items = await self._items(
            OpportunityNewsRecord.opportunity_id == opportunity_id
        )
        return ImpactNews(checked_at=checked_at, items=items[opportunity_id])

    async def feed(self) -> dict[uuid.UUID, ImpactNews]:
        """News of every opportunity that was searched at least once."""
        checked = await self._session.execute(
            select(OpportunityRecord.id, OpportunityRecord.news_checked_at).where(
                OpportunityRecord.news_checked_at.is_not(None)
            )
        )
        items = await self._items(
            OpportunityNewsRecord.opportunity_id.in_(
                select(OpportunityRecord.id).where(
                    OpportunityRecord.news_checked_at.is_not(None)
                )
            )
        )
        return {
            opportunity_id: ImpactNews(
                checked_at=checked_at, items=items[opportunity_id]
            )
            for opportunity_id, checked_at in checked.all()
        }

    async def _items(
        self, condition: ColumnElement[bool]
    ) -> defaultdict[uuid.UUID, tuple[ImpactNewsItem, ...]]:
        result = await self._session.execute(
            select(OpportunityNewsRecord)
            .where(condition)
            .order_by(
                OpportunityNewsRecord.published_on.desc().nulls_last(),
                OpportunityNewsRecord.found_at.desc(),
            )
        )
        grouped: defaultdict[uuid.UUID, list[ImpactNewsItem]] = defaultdict(list)
        for r in result.scalars().all():
            grouped[r.opportunity_id].append(
                ImpactNewsItem(
                    level=r.level,
                    kind=r.kind,
                    url=r.url,
                    title=r.title,
                    snippet=r.snippet,
                    published_on=r.published_on,
                    found_at=r.found_at,
                )
            )
        return defaultdict(tuple, {k: tuple(v) for k, v in grouped.items()})


def parse_published(value: str | None) -> date | None:
    """Tavily dates come as RFC 2822 ("Fri, 04 Sep 2026 15:04:45 GMT"),
    sometimes ISO; anything else is unknown."""
    if not value:
        return None
    try:
        return parsedate_to_datetime(value).date()
    except TypeError, ValueError:
        pass
    try:
        return date.fromisoformat(value[:10])
    except ValueError:
        return None
