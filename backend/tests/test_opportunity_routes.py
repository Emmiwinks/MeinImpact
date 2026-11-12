"""GET /v1/opportunities/pool and /preview, POST /v1/opportunities/tracked."""

import logging
import uuid
from dataclasses import replace
from datetime import UTC, date, datetime
from typing import Any
from uuid import uuid4

from fastapi.testclient import TestClient

from meinimpact.api.dependencies import get_opportunity_repository
from meinimpact.api.routes.opportunities import PREVIEW_SIZE, preview_selection
from meinimpact.core.config import Settings
from meinimpact.domain.entities import Opportunity
from meinimpact.main import create_app

_OPPORTUNITY = Opportunity(
    id=uuid.UUID(int=1),
    source_org="openPetition",
    source_url="https://www.openpetition.de/petition/online/kita",
    kind="petition",
    status="open",
    region="dresden",
    locality="Dresden",
    organizer=None,
    title="Soll die Kita erhalten bleiben?",
    summary="Die Stadt plant die Schließung.",
    affected_tags=("Familie/Kinder",),
    lebenslagen=("eltern", "kita_kinder"),
    werte_relevanz={},
    pro_argumente=("Betreuungsplätze",),
    contra_argumente=("Kosten",),
    personal_impact_snippets={"hat_kinder:true": "Betrifft deine Kita-Wahl."},
    everyday_relevance=5,
    accessibility=4,
    districts=("Hellerau",),
    opens_on=None,
    closes_on=date(2027, 1, 3),
    support_count=445,
    support_goal=None,
    support_count_as_of=datetime(2026, 11, 1, tzinfo=UTC),
    first_seen_at=datetime(2026, 11, 1, tzinfo=UTC),
)


class FakeRepository:
    def __init__(self) -> None:
        self.asked_for: date | None = None
        self.tracked: dict[uuid.UUID, date] = {}
        self.commits = 0
        self.open = [_OPPORTUNITY]

    async def list_open(self, today: date) -> list[Opportunity]:
        self.asked_for = today
        return self.open

    async def mark_tracked(self, opportunity_id: uuid.UUID, today: date) -> bool:
        if opportunity_id != _OPPORTUNITY.id:
            return False
        self.tracked.setdefault(opportunity_id, today)
        return True

    async def commit(self) -> None:
        self.commits += 1


def _client(repository: FakeRepository) -> TestClient:
    app = create_app(Settings(jwt_secret="test-secret"))
    app.dependency_overrides[get_opportunity_repository] = lambda: repository
    return TestClient(app)


def _auth(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/v1/auth/anonymous-session",
        json={"installation_id": str(uuid4()), "app_version": "0.1.0"},
    )
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_pool_requires_a_session() -> None:
    assert _client(FakeRepository()).get("/v1/opportunities/pool").status_code == 401


def test_pool_serves_open_opportunities_for_today() -> None:
    repository = FakeRepository()
    client = _client(repository)

    response = client.get("/v1/opportunities/pool", headers=_auth(client))

    assert response.status_code == 200
    assert repository.asked_for == datetime.now(UTC).date()
    [item] = response.json()["opportunities"]
    assert item["title"] == "Soll die Kita erhalten bleiben?"
    assert item["kind"] == "petition"
    assert item["closes_on"] == "2027-01-03"
    assert item["support_count"] == 445
    assert (item["everyday_relevance"], item["accessibility"]) == (5, 4)
    assert item["districts"] == ["Hellerau"]
    assert item["lebenslagen"] == ["eltern", "kita_kinder"]
    assert item["personal_impact_snippets"] == {
        "hat_kinder:true": "Betrifft deine Kita-Wahl."
    }


def _variant(n: int, **changes: Any) -> Opportunity:
    return replace(
        _OPPORTUNITY, id=uuid.UUID(int=100 + n), title=f"Frage {n}", **changes
    )


def test_preview_needs_no_session_and_counts_by_level() -> None:
    repository = FakeRepository()
    repository.open = [
        _OPPORTUNITY,
        _variant(1, region="eu", affected_tags=("Wohnen/Miete",)),
        _variant(2, region="bund", accessibility=2),
    ]

    response = _client(repository).get("/v1/opportunities/preview")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=900"
    body = response.json()
    assert body["total"] == 3
    assert body["by_region"] == {"dresden": 1, "sachsen": 0, "bund": 1, "eu": 1}
    # The hard-to-grasp Bund item stays out; Wohnen/Miete is the first topic.
    assert [(i["title"], i["topic_index"]) for i in body["items"]] == [
        ("Soll die Kita erhalten bleiben?", 13),
        ("Frage 1", 0),
    ]
    kita = body["items"][0]
    assert kita["for_you"] == "Betrifft deine Kita-Wahl."
    assert (kita["pro_argumente"], kita["contra_argumente"]) == (
        ["Betreuungsplätze"],
        ["Kosten"],
    )
    assert (kita["source_org"], kita["summary"]) == (
        "openPetition",
        "Die Stadt plant die Schließung.",
    )
    assert (kita["support_count"], kita["place"], kita["districts"]) == (
        445,
        "Dresden",
        ["Hellerau"],
    )


def test_preview_selection_takes_levels_in_turn_soonest_first() -> None:
    items = [
        _variant(1, region="eu", closes_on=date(2026, 12, 1)),
        _variant(2, region="dresden", closes_on=None),
        _variant(3, region="dresden", closes_on=date(2026, 11, 20)),
        _variant(4, region="eu", closes_on=date(2026, 11, 15)),
    ]

    picked = preview_selection(items)

    assert [o.title for o in picked] == ["Frage 3", "Frage 4", "Frage 2", "Frage 1"]


def test_preview_selection_stops_at_the_preview_size() -> None:
    items = [_variant(n) for n in range(PREVIEW_SIZE + 5)]
    assert len(preview_selection(items)) == PREVIEW_SIZE


def test_tracked_requires_a_session() -> None:
    response = _client(FakeRepository()).post(
        "/v1/opportunities/tracked", json={"opportunity_id": str(_OPPORTUNITY.id)}
    )
    assert response.status_code == 401


def test_tracked_marks_the_opportunity_once() -> None:
    repository = FakeRepository()
    client = _client(repository)
    headers = _auth(client)
    body = {"opportunity_id": str(_OPPORTUNITY.id)}

    first = client.post("/v1/opportunities/tracked", json=body, headers=headers)
    second = client.post("/v1/opportunities/tracked", json=body, headers=headers)

    assert first.status_code == second.status_code == 200
    assert repository.tracked == {_OPPORTUNITY.id: datetime.now(UTC).date()}
    assert repository.commits == 2


def test_tracked_unknown_opportunity_is_404() -> None:
    repository = FakeRepository()
    client = _client(repository)

    response = client.post(
        "/v1/opportunities/tracked",
        json={"opportunity_id": str(uuid.UUID(int=2))},
        headers=_auth(client),
    )

    assert response.status_code == 404
    assert repository.commits == 0


def test_access_log_skips_tracked_but_keeps_other_paths() -> None:
    create_app(Settings(jwt_secret="test-secret"))
    access = logging.getLogger("uvicorn.access")

    def logged(path: str) -> bool:
        record = access.makeRecord(
            "uvicorn.access",
            logging.INFO,
            __file__,
            0,
            '%s - "%s %s HTTP/%s" %d',
            ("10.0.0.1:5000", "POST", path, "1.1", 200),
            None,
        )
        # Since Python 3.12 a filter may hand back a changed record
        return bool(access.filter(record))

    assert not logged("/v1/opportunities/tracked")
    assert logged("/v1/opportunities/pool")
