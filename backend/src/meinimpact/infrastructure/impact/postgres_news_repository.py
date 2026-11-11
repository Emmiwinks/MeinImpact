"""News about tracked opportunities in Postgres.

Every relevant hit of every ladder run is kept with its rung; what the app
shows is decided when reading (`ImpactNews.shown`), the same rule as
`LadderResult.items`, applied across all runs.
"""

import uuid
from dataclasses import dataclass
from datetime import date, datetime
from email.utils import parsedate_to_datetime

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.impact.news_ladder import BACKGROUND, LadderResult
from meinimpact.infrastructure.models import OpportunityNewsRecord, OpportunityRecord

_SNIPPET_CHARS = 600


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


class PostgresImpactNewsRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def commit(self) -> None:
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

    async def news_for(self, opportunity_id: uuid.UUID) -> ImpactNews:
        checked_at = await self._session.scalar(
            select(OpportunityRecord.news_checked_at).where(
                OpportunityRecord.id == opportunity_id
            )
        )
        result = await self._session.execute(
            select(OpportunityNewsRecord)
            .where(OpportunityNewsRecord.opportunity_id == opportunity_id)
            .order_by(
                OpportunityNewsRecord.published_on.desc().nulls_last(),
                OpportunityNewsRecord.found_at.desc(),
            )
        )
        return ImpactNews(
            checked_at=checked_at,
            items=tuple(
                ImpactNewsItem(
                    level=r.level,
                    kind=r.kind,
                    url=r.url,
                    title=r.title,
                    snippet=r.snippet,
                    published_on=r.published_on,
                    found_at=r.found_at,
                )
                for r in result.scalars().all()
            ),
        )


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
