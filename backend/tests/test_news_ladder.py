"""The Mein Impact news ladder: rungs, judging, Tavily request."""

import json
from collections.abc import Sequence
from datetime import date
from typing import Any

import httpx

from meinimpact.infrastructure.impact.news_ladder import (
    BACKGROUND,
    EXACT,
    ISSUE,
    ImpactSubject,
    NewsLadder,
    SearchHit,
    TavilySearch,
    parse_judgments,
)

SUBJECT = ImpactSubject(
    kind="decision",
    title="Imbisspavillons auf der Prager Straße erhalten",
    summary="Der Stadtbezirksbeirat Altstadt berät.",
    organizer="Stadtbezirksbeirat Altstadt",
    locality="Dresden",
    source_url="https://www.ratsinfo-example.de/vo0050.asp?__kvonr=31070",
    since=date(2026, 5, 1),
)

QUERIES = {
    EXACT: "Imbisspavillons Prager Straße Dresden",
    ISSUE: "Imbisse Altstadt Dresden",
    BACKGROUND: "Innenstadt Gastronomie Dresden",
}


def _hit(name: str) -> SearchHit:
    return SearchHit(title=name, url=f"https://news.example/{name}", content=name)


class FakeCompleter:
    """Answers the query prompt with QUERIES; judges every hit whose title
    is in `relevant` as relevant news."""

    def __init__(self, relevant: set[str]) -> None:
        self._relevant = relevant

    async def complete_json(self, prompt: str) -> dict[str, Any]:
        if "Suchanfragen" in prompt:
            return dict(QUERIES)
        titles = [
            line.split("] ", 1)[1] for line in prompt.splitlines() if line[:1] == "["
        ]
        return {
            "results": [
                {"i": i, "relevant": title in self._relevant, "kind": "news"}
                for i, title in enumerate(titles)
            ]
        }


class FakeSearch:
    def __init__(self, hits: dict[str, list[SearchHit]]) -> None:
        self._hits = hits
        self.queries: list[str] = []
        self.excluded: Sequence[str] = ()

    async def search(
        self, query: str, *, since: date, exclude_domains: Sequence[str]
    ) -> list[SearchHit]:
        self.queries.append(query)
        self.excluded = exclude_domains
        return self._hits.get(query, [])


async def test_stops_at_the_first_rung_with_a_relevant_hit() -> None:
    search = FakeSearch({QUERIES[EXACT]: [_hit("mdr"), _hit("werbung")]})
    ladder = NewsLadder(FakeCompleter({"mdr"}), search)

    result = await ladder.run(SUBJECT)

    assert search.queries == [QUERIES[EXACT]]
    assert [j.hit.title for j in result.items] == ["mdr"]


async def test_exhaustive_searches_every_rung() -> None:
    search = FakeSearch({QUERIES[EXACT]: [_hit("mdr")]})
    ladder = NewsLadder(FakeCompleter({"mdr"}), search)

    result = await ladder.run(SUBJECT, exhaustive=True)

    assert search.queries == list(QUERIES.values())
    assert [r.level for r in result.rungs] == [EXACT, ISSUE, BACKGROUND]


async def test_background_alone_yields_at_most_one_item() -> None:
    search = FakeSearch(
        {QUERIES[BACKGROUND]: [_hit("dnn"), _hit("tag24")], QUERIES[EXACT]: []}
    )
    ladder = NewsLadder(FakeCompleter({"dnn", "tag24"}), search)

    result = await ladder.run(SUBJECT)

    assert [j.hit.title for j in result.items] == ["dnn"]


async def test_nothing_found_is_an_empty_result() -> None:
    ladder = NewsLadder(FakeCompleter(set()), FakeSearch({}))

    assert (await ladder.run(SUBJECT)).items == ()


async def test_excludes_social_media_and_the_actions_own_site() -> None:
    search = FakeSearch({})
    await NewsLadder(FakeCompleter(set()), search).run(SUBJECT)

    assert "instagram.com" in search.excluded
    assert "ratsinfo-example.de" in search.excluded


def test_unjudged_garbled_and_own_pages_are_not_relevant() -> None:
    hits = [_hit("a"), _hit("b"), _hit("c"), _hit("d")]
    answer = {
        "results": [
            {"i": 0, "relevant": True, "kind": "news", "reason": "passt"},
            {"i": 1, "relevant": "yes", "kind": "news"},
            {"i": 2, "relevant": True, "kind": "action_page"},
            {"i": "3", "relevant": True},
        ]
    }

    judged = parse_judgments(answer, hits)

    assert [j.relevant for j in judged] == [True, False, False, False]
    assert judged[0].reason == "passt"
    assert judged[3].kind == "other"


async def test_tavily_sends_date_country_exclusions_and_parses_hits() -> None:
    sent: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        sent.update(json.loads(request.content))
        assert request.headers["Authorization"] == "Bearer key"
        return httpx.Response(
            200,
            json={
                "results": [
                    {
                        "title": "Imbisse müssen weg",
                        "url": "https://www.mdr.de/x",
                        "content": "Die Pavillons ...",
                        "published_date": "2026-10-01",
                    },
                    {"title": "ohne url"},
                ]
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    search = TavilySearch("key", client=client)

    hits = await search.search(
        "Imbisspavillons", since=date(2026, 5, 1), exclude_domains=["x.com"]
    )

    assert sent["start_date"] == "2026-05-01"
    assert sent["country"] == "germany"
    assert sent["exclude_domains"] == ["x.com"]
    assert hits == [
        SearchHit(
            title="Imbisse müssen weg",
            url="https://www.mdr.de/x",
            content="Die Pavillons ...",
            published_date="2026-10-01",
        )
    ]


async def test_tavily_failure_is_no_hits() -> None:
    client = httpx.AsyncClient(
        transport=httpx.MockTransport(lambda _: httpx.Response(500))
    )

    assert (
        await TavilySearch("key", client=client).search(
            "x", since=date(2026, 5, 1), exclude_domains=[]
        )
        == []
    )
