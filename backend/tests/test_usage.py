"""POST /v1/usage and the anonymous counters behind it."""

from datetime import date, datetime
from zoneinfo import ZoneInfo

from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession

from meinimpact.api.dependencies import get_usage_repository
from meinimpact.core.config import Settings
from meinimpact.infrastructure.usage.postgres_usage_repository import (
    PostgresUsageRepository,
)
from meinimpact.main import create_app


class FakeUsage:
    def __init__(self) -> None:
        self.counted: list[tuple[str, date]] = []
        self.commits = 0

    async def count(self, event: str, day: date) -> None:
        self.counted.append((event, day))

    async def commit(self) -> None:
        self.commits += 1


def _client(usage: FakeUsage) -> TestClient:
    app = create_app(Settings(jwt_secret="test-secret"))
    app.dependency_overrides[get_usage_repository] = lambda: usage
    return TestClient(app)


def _auth(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/v1/auth/anonymous-session",
        json={
            "installation_id": "00000000-0000-4000-8000-000000000001",
            "app_version": "0.1.0",
        },
    )
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_usage_requires_a_session() -> None:
    response = _client(FakeUsage()).post("/v1/usage", json={"event": "action_done"})
    assert response.status_code == 401


def test_usage_counts_the_event_on_the_berlin_day() -> None:
    usage = FakeUsage()
    client = _client(usage)

    response = client.post(
        "/v1/usage", json={"event": "card_turned"}, headers=_auth(client)
    )

    assert response.status_code == 200
    today = datetime.now(ZoneInfo("Europe/Berlin")).date()
    assert usage.counted == [("card_turned", today)]
    assert usage.commits == 1


def test_unknown_event_is_rejected() -> None:
    usage = FakeUsage()
    client = _client(usage)

    response = client.post("/v1/usage", json={"event": "who"}, headers=_auth(client))

    assert response.status_code == 422
    assert usage.counted == []


async def test_counts_add_up_per_day_and_event(db_session: AsyncSession) -> None:
    repository = PostgresUsageRepository(db_session)
    # Long past, so no real counts get in the way
    monday, tuesday = date(2001, 1, 1), date(2001, 1, 2)

    for _ in range(3):
        await repository.count("action_done", monday)
    await repository.count("active_day", monday)
    await repository.count("action_done", tuesday)

    assert await repository.since(monday) == {
        monday: {"action_done": 3, "active_day": 1},
        tuesday: {"action_done": 1},
    }
    assert await repository.since(tuesday) == {tuesday: {"action_done": 1}}
