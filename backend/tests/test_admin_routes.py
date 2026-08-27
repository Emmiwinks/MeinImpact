"""Tests for the admin ingestion-trigger route."""

from collections.abc import AsyncIterator
from datetime import UTC, datetime
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from fastapi.testclient import TestClient

from meinimpact.api.dependencies import get_db_session
from meinimpact.core.config import Settings
from meinimpact.main import create_app


class _FakeResult:
    def __init__(self, row: dict[str, object] | None) -> None:
        self._row = row

    def mappings(self) -> _FakeResult:
        return self

    def first(self) -> dict[str, object] | None:
        return self._row


class _FakeSession:
    def __init__(self, row: dict[str, object] | None) -> None:
        self._row = row

    async def execute(self, *args: object, **kwargs: object) -> _FakeResult:
        return _FakeResult(self._row)


def _client_with_settings(admin_api_key: str | None) -> TestClient:
    app = create_app(Settings(admin_api_key=admin_api_key))
    row = {
        "id": uuid4(),
        "ran_at": datetime(2026, 7, 15, 3, 0, tzinfo=UTC),
        "parliamentary_actions_found": 5,
        "petition_actions_found": 3,
        "state_a_count": 2,
        "state_b_count": 1,
        "state_c_count": 4,
        "state_d_discarded": 1,
        "inserted_count": 7,
        "duration_seconds": 12.3,
        "errors": [],
    }

    async def _fake_db_session() -> AsyncIterator[_FakeSession]:
        yield _FakeSession(row)

    app.dependency_overrides[get_db_session] = _fake_db_session
    return TestClient(app)


def test_missing_key_is_forbidden() -> None:
    client = _client_with_settings(admin_api_key="secret")
    response = client.post("/v1/admin/ingestion/run")
    assert response.status_code == 403


def test_wrong_key_is_forbidden() -> None:
    client = _client_with_settings(admin_api_key="secret")
    response = client.post(
        "/v1/admin/ingestion/run", headers={"X-Admin-Api-Key": "wrong"}
    )
    assert response.status_code == 403


def test_unconfigured_admin_key_rejects_everything() -> None:
    client = _client_with_settings(admin_api_key=None)
    response = client.post(
        "/v1/admin/ingestion/run", headers={"X-Admin-Api-Key": "anything"}
    )
    assert response.status_code == 403


def test_correct_key_triggers_ingestion_and_returns_run_summary() -> None:
    client = _client_with_settings(admin_api_key="secret")
    with patch(
        "meinimpact.api.routes.admin.run_ingestion_pipeline",
        new_callable=AsyncMock,
    ) as mock_run:
        response = client.post(
            "/v1/admin/ingestion/run", headers={"X-Admin-Api-Key": "secret"}
        )
    assert response.status_code == 200
    mock_run.assert_awaited_once()
    body = response.json()
    assert body["parliamentary_actions_found"] == 5
    assert body["state_c_count"] == 4
