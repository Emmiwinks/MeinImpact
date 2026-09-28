"""Tests for the admin ingestion-trigger route."""

from collections.abc import AsyncIterator
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from meinimpact.api.dependencies import get_db_session
from meinimpact.core.config import Settings
from meinimpact.infrastructure.pipeline.opportunity_pipeline import IngestionSummary
from meinimpact.main import create_app


def _client_with_settings(
    admin_api_key: str | None,
    *,
    tavily_api_key: str | None = "tavily-key",
    mistral_api_key: str | None = "mistral-key",
) -> TestClient:
    app = create_app(
        Settings(
            admin_api_key=admin_api_key,
            tavily_api_key=tavily_api_key,
            mistral_api_key=mistral_api_key,
        )
    )

    async def _fake_db_session() -> AsyncIterator[object]:
        yield object()

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


def test_missing_provider_keys_returns_service_unavailable() -> None:
    client = _client_with_settings(admin_api_key="secret", tavily_api_key=None)
    response = client.post(
        "/v1/admin/ingestion/run", headers={"X-Admin-Api-Key": "secret"}
    )
    assert response.status_code == 503


def test_correct_key_runs_ingestion_and_returns_summary() -> None:
    client = _client_with_settings(admin_api_key="secret")
    fake_summary = IngestionSummary(
        fetched=10, actionable=4, inserted=3, refreshed=1, errors=["one error"]
    )
    with patch(
        "meinimpact.api.routes.admin.run_ingestion",
        new_callable=AsyncMock,
        return_value=fake_summary,
    ) as mock_run:
        response = client.post(
            "/v1/admin/ingestion/run", headers={"X-Admin-Api-Key": "secret"}
        )

    assert response.status_code == 200
    mock_run.assert_awaited_once()
    body = response.json()
    assert body == {
        "fetched": 10,
        "actionable": 4,
        "inserted": 3,
        "refreshed": 1,
        "errors": ["one error"],
    }
