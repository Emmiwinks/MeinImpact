"""GET /v1/opportunities/pool and POST /v1/opportunities/tracked."""

import logging
import uuid
from datetime import UTC, date, datetime
from uuid import uuid4

from fastapi.testclient import TestClient

from meinimpact.api.dependencies import get_opportunity_repository
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

    async def list_open(self, today: date) -> list[Opportunity]:
        self.asked_for = today
        return [_OPPORTUNITY]

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
