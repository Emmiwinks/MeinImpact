"""Storing news about tracked opportunities, and what the app is shown."""

from datetime import UTC, date, datetime, timedelta

from listing_fakes import NOW, make_listing
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.infrastructure.impact.news_ladder import (
    BACKGROUND,
    EXACT,
    ISSUE,
    JudgedHit,
    LadderResult,
    Rung,
    SearchHit,
)
from meinimpact.infrastructure.impact.postgres_news_repository import (
    ImpactNews,
    ImpactNewsItem,
    PostgresImpactNewsRepository,
    parse_published,
)
from meinimpact.infrastructure.models import OpportunityRecord
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
)

FIRST = datetime(2026, 11, 11, 6, tzinfo=UTC)
SECOND = FIRST + timedelta(days=2)


def _judged(
    name: str, *, relevant: bool = True, published: str | None = None
) -> JudgedHit:
    return JudgedHit(
        hit=SearchHit(
            title=name,
            url=f"https://news.example/{name}",
            content=name,
            published_date=published,
        ),
        relevant=relevant,
        kind="news",
        reason="Über die Sache.",
    )


def _result(*rungs: tuple[str, tuple[JudgedHit, ...]]) -> LadderResult:
    return LadderResult(
        queries={},
        rungs=tuple(Rung(level=level, query="q", hits=hits) for level, hits in rungs),
    )


async def _opportunity(session: AsyncSession) -> OpportunityRecord:
    await PostgresOpportunityRepository(session).sync(
        [make_listing("a")], complete_source_ids={"src"}, observed_at=NOW
    )
    result = await session.execute(
        select(OpportunityRecord).where(OpportunityRecord.external_id == "a")
    )
    return result.scalar_one()


async def test_relevant_hits_accumulate_across_runs(db_session: AsyncSession) -> None:
    record = await _opportunity(db_session)
    repository = PostgresImpactNewsRepository(db_session)

    first = await repository.save(
        record.id,
        _result(
            (
                EXACT,
                (
                    _judged("mdr", published="Fri, 04 Sep 2026 15:04:45 GMT"),
                    _judged("werbung", relevant=False),
                ),
            )
        ),
        checked_at=FIRST,
    )
    # Same article again, plus a new one
    second = await repository.save(
        record.id,
        _result((ISSUE, (_judged("mdr"), _judged("dnn", published="2026-10-01")))),
        checked_at=SECOND,
    )

    assert (first, second) == (1, 1)
    news = await repository.news_for(record.id)
    assert news.checked_at == SECOND
    assert [(i.title, i.level, i.published_on) for i in news.items] == [
        ("dnn", ISSUE, date(2026, 10, 1)),
        ("mdr", EXACT, date(2026, 9, 4)),
    ]
    # The first find is kept
    assert news.items[1].found_at == FIRST


async def test_a_run_without_finds_still_counts_as_checked(
    db_session: AsyncSession,
) -> None:
    record = await _opportunity(db_session)
    repository = PostgresImpactNewsRepository(db_session)
    assert await repository.news_for(record.id) == ImpactNews(checked_at=None, items=())

    added = await repository.save(record.id, _result((EXACT, ())), checked_at=FIRST)

    assert added == 0
    assert await repository.news_for(record.id) == ImpactNews(
        checked_at=FIRST, items=()
    )


def _item(title: str, level: str) -> ImpactNewsItem:
    return ImpactNewsItem(
        level=level,
        kind="news",
        url=f"https://news.example/{title}",
        title=title,
        snippet="",
        published_on=None,
        found_at=FIRST,
    )


def test_specific_news_hides_background() -> None:
    news = ImpactNews(
        checked_at=FIRST,
        items=(_item("thema", BACKGROUND), _item("sache", EXACT), _item("ort", ISSUE)),
    )

    assert [i.title for i in news.shown] == ["sache", "ort"]


def test_background_alone_shows_one_item() -> None:
    news = ImpactNews(
        checked_at=FIRST,
        items=(_item("neu", BACKGROUND), _item("alt", BACKGROUND)),
    )

    assert [i.title for i in news.shown] == ["neu"]


def test_published_dates_in_both_tavily_formats() -> None:
    assert parse_published("Fri, 16 Oct 2026 16:00:00 GMT") == date(2026, 10, 16)
    assert parse_published("2026-10-16T08:00:00Z") == date(2026, 10, 16)
    assert parse_published("gestern") is None
    assert parse_published(None) is None
