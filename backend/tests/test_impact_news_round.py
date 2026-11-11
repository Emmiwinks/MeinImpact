"""The scheduled Mein Impact news round: what is due, the daily budget,
failures, and the app's news feed."""

import uuid
from collections.abc import Mapping, Sequence
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any
from uuid import uuid4

from fastapi.testclient import TestClient
from listing_fakes import NOW, make_listing
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.api.dependencies import get_impact_news_repository
from meinimpact.core.config import Settings
from meinimpact.infrastructure.impact.news_ladder import BACKGROUND, EXACT, SearchHit
from meinimpact.infrastructure.impact.postgres_news_repository import (
    ImpactNews,
    ImpactNewsItem,
    PostgresImpactNewsRepository,
)
from meinimpact.infrastructure.models import OpportunityRecord
from meinimpact.infrastructure.opportunities.postgres_opportunity_repository import (
    PostgresOpportunityRepository,
)
from meinimpact.main import create_app
from meinimpact.services.impact_news import Prices, run_news_round
from tests.test_news_ladder import QUERIES, FakeCompleter, FakeSearch

MOMENT = datetime(2030, 1, 15, 9, tzinfo=UTC)
PRICES = Prices.from_settings(Settings())
WEEK = timedelta(days=7)
# One search that finds on the first rung: 1 credit and two Mistral calls
# of 1000 + 100 tokens
ONE_SEARCH = Decimal("0.008") + 2 * Decimal("0.00225")


class MeteredCompleter(FakeCompleter):
    def __init__(self, relevant: set[str], *, fail_judging: bool = False) -> None:
        super().__init__(relevant)
        self._fail_judging = fail_judging
        self.prompt_tokens = 0
        self.completion_tokens = 0

    async def complete_json(self, prompt: str) -> dict[str, Any]:
        # A failed call reports no usage
        if self._fail_judging and "Treffer" in prompt:
            raise RuntimeError("Mistral down")
        self.prompt_tokens += 1000
        self.completion_tokens += 100
        return await super().complete_json(prompt)


class MeteredSearch(FakeSearch):
    def __init__(self, hits: dict[str, list[SearchHit]]) -> None:
        super().__init__(hits)
        self.credits = 0

    async def search(
        self, query: str, *, since: date, exclude_domains: Sequence[str]
    ) -> list[SearchHit]:
        self.credits += 1
        return await super().search(query, since=since, exclude_domains=exclude_domains)


def _search() -> MeteredSearch:
    hit = SearchHit(
        title="mdr",
        url="https://www.mdr.de/x",
        content="Die Pavillons",
        published_date="Fri, 04 Sep 2026 15:04:45 GMT",
    )
    return MeteredSearch({QUERIES[EXACT]: [hit]})


async def _opportunities(
    session: AsyncSession, **tracked: datetime | None
) -> dict[str, OpportunityRecord]:
    """Relevant opportunities by external id; each keyword is tracked and
    was last checked at its value. "untracked" is neither."""
    # Only this test's opportunities are due
    await session.execute(update(OpportunityRecord).values(tracked_since=None))
    names = [*tracked, "untracked"]
    await PostgresOpportunityRepository(session).sync(
        [make_listing(name) for name in names],
        complete_source_ids=set(),
        observed_at=NOW,
    )
    result = await session.execute(
        select(OpportunityRecord).where(OpportunityRecord.external_id.in_(names))
    )
    records = {r.external_id: r for r in result.scalars().all()}
    for name, record in records.items():
        record.is_relevant = True
        if name in tracked:
            record.tracked_since = date(2030, 1, 1)
            record.news_checked_at = tracked[name]
    await session.commit()
    return records


async def test_searches_every_due_tracked_opportunity_and_records_spend(
    committing_db_session: AsyncSession,
) -> None:
    records = await _opportunities(
        committing_db_session,
        never=None,
        last_month=MOMENT - timedelta(days=30),
        yesterday=MOMENT - timedelta(days=1),
    )
    repository = PostgresImpactNewsRepository(committing_db_session)

    summary = await run_news_round(
        repository,
        MeteredCompleter({"mdr"}),
        _search(),
        prices=PRICES,
        daily_budget=Decimal(1),
        recheck_after=WEEK,
        now=lambda: MOMENT,
    )

    assert (summary.searched, summary.new_items, summary.stopped) == (
        2,
        2,
        "nothing_due",
    )
    assert summary.spent_eur == 2 * ONE_SEARCH
    assert await repository.spent_on(MOMENT.date()) == 2 * ONE_SEARCH
    news = await repository.news_for(records["never"].id)
    assert news.checked_at == MOMENT
    assert [i.title for i in news.items] == ["mdr"]
    for skipped in ("yesterday", "untracked"):
        assert (await repository.news_for(records[skipped].id)).items == ()


async def test_stops_when_the_budget_could_not_cover_one_more_search(
    committing_db_session: AsyncSession,
) -> None:
    await _opportunities(committing_db_session, first=None, second=None)
    repository = PostgresImpactNewsRepository(committing_db_session)

    summary = await run_news_round(
        repository,
        MeteredCompleter({"mdr"}),
        _search(),
        prices=PRICES,
        # Room for the worst case once, not after one real search
        daily_budget=PRICES.worst_case_search + Decimal("0.01"),
        recheck_after=WEEK,
        now=lambda: MOMENT,
    )

    assert (summary.searched, summary.stopped) == (1, "budget")


async def test_a_failed_search_is_paid_given_back_and_ends_the_round(
    committing_db_session: AsyncSession,
) -> None:
    records = await _opportunities(committing_db_session, first=None, second=None)
    repository = PostgresImpactNewsRepository(committing_db_session)

    summary = await run_news_round(
        repository,
        MeteredCompleter({"mdr"}, fail_judging=True),
        _search(),
        prices=PRICES,
        daily_budget=Decimal(1),
        recheck_after=WEEK,
        now=lambda: MOMENT,
    )

    assert (summary.searched, summary.stopped) == (0, "error")
    # The search ran and the query call was answered before judging failed
    assert summary.spent_eur == Decimal("0.008") + Decimal("0.00225")
    assert await repository.spent_on(MOMENT.date()) == summary.spent_eur
    for record in records.values():
        assert (await repository.news_for(record.id)).checked_at is None


def test_worst_case_search_with_the_configured_prices() -> None:
    # 3 credits at 0.008 + 4 calls of 4000 prompt and 1200 answer tokens
    assert PRICES.worst_case_search == Decimal("0.084")


# ── Feed endpoint ─────────────────────────────────────────────────────────────

_FOUND = uuid.UUID(int=1)
_NOTHING = uuid.UUID(int=2)


def _item(title: str, level: str) -> ImpactNewsItem:
    return ImpactNewsItem(
        level=level,
        kind="news",
        url=f"https://news.example/{title}",
        title=title,
        snippet="Auszug",
        published_on=date(2026, 9, 4),
        found_at=MOMENT,
    )


class FakeNewsRepository:
    async def feed(self) -> dict[uuid.UUID, ImpactNews]:
        return {
            _FOUND: ImpactNews(
                checked_at=MOMENT,
                items=(_item("thema", BACKGROUND), _item("sache", EXACT)),
            ),
            _NOTHING: ImpactNews(checked_at=MOMENT, items=()),
        }


def _auth(client: TestClient) -> Mapping[str, str]:
    response = client.post(
        "/v1/auth/anonymous-session",
        json={"installation_id": str(uuid4()), "app_version": "0.1.0"},
    )
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_news_feed_serves_what_the_app_shows_for_every_searched_action() -> None:
    app = create_app(Settings(jwt_secret="test-secret"))
    app.dependency_overrides[get_impact_news_repository] = FakeNewsRepository
    client = TestClient(app)

    response = client.get("/v1/opportunities/news", headers=_auth(client))

    assert response.status_code == 200
    assert response.json() == {
        "opportunities": [
            {
                "opportunity_id": str(_FOUND),
                "checked_at": "2030-01-15T09:00:00Z",
                "items": [
                    {
                        "level": "exact",
                        "kind": "news",
                        "title": "sache",
                        "url": "https://news.example/sache",
                        "snippet": "Auszug",
                        "published_on": "2026-09-04",
                    }
                ],
            },
            {
                "opportunity_id": str(_NOTHING),
                "checked_at": "2030-01-15T09:00:00Z",
                "items": [],
            },
        ]
    }
