"""Tests for the admin ingestion-trigger route."""

from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from meinimpact.api.routes import admin
from meinimpact.core.config import Settings
from meinimpact.infrastructure.pipeline.ingestion import IngestionSummary
from meinimpact.main import create_app

_HEADERS = {"X-Admin-Api-Key": "secret"}


def _client(
    admin_api_key: str | None = "secret", mistral_api_key: str | None = "key"
) -> TestClient:
    settings = Settings(admin_api_key=admin_api_key, mistral_api_key=mistral_api_key)
    return TestClient(create_app(settings))


def test_missing_key_is_forbidden() -> None:
    assert _client().post("/v1/admin/ingestion/run").status_code == 403


def test_wrong_key_is_forbidden() -> None:
    response = _client().post(
        "/v1/admin/ingestion/run", headers={"X-Admin-Api-Key": "wrong"}
    )
    assert response.status_code == 403


def test_unconfigured_admin_key_rejects_everything() -> None:
    response = _client(admin_api_key=None).post(
        "/v1/admin/ingestion/run", headers=_HEADERS
    )
    assert response.status_code == 403


def test_missing_mistral_key_returns_service_unavailable() -> None:
    response = _client(mistral_api_key=None).post(
        "/v1/admin/ingestion/run", headers=_HEADERS
    )
    assert response.status_code == 503


def test_correct_key_starts_ingestion_in_background() -> None:
    with patch(
        "meinimpact.api.routes.admin.run_configured_ingestion",
        new_callable=AsyncMock,
        return_value=IngestionSummary(listed=3),
    ) as run:
        response = _client().post("/v1/admin/ingestion/run", headers=_HEADERS)

    assert response.status_code == 202
    assert response.json() == {"status": "started"}
    run.assert_awaited_once()
    assert not admin._ingestion_lock.locked()


def test_failed_run_releases_the_lock() -> None:
    with patch(
        "meinimpact.api.routes.admin.run_configured_ingestion",
        new_callable=AsyncMock,
        side_effect=RuntimeError("boom"),
    ):
        response = _client().post("/v1/admin/ingestion/run", headers=_HEADERS)

    assert response.status_code == 202
    assert not admin._ingestion_lock.locked()


async def test_concurrent_run_is_rejected() -> None:
    await admin._ingestion_lock.acquire()
    try:
        response = _client().post("/v1/admin/ingestion/run", headers=_HEADERS)
    finally:
        admin._ingestion_lock.release()

    assert response.status_code == 409
