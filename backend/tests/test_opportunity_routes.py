"""GET /v1/opportunities/pool."""

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
    werte_relevanz={},
    pro_argumente=("Betreuungsplätze",),
    contra_argumente=("Kosten",),
    personal_impact_snippets={"hat_kinder:true": "Betrifft deine Kita-Wahl."},
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

    async def list_open(self, today: date) -> list[Opportunity]:
        self.asked_for = today
        return [_OPPORTUNITY]


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
    assert item["personal_impact_snippets"] == {
        "hat_kinder:true": "Betrifft deine Kita-Wahl."
    }
