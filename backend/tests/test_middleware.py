"""Middleware tests."""

from fastapi.testclient import TestClient

from meinimpact.core.config import Settings
from meinimpact.main import create_app


def test_request_size_limit_rejects_large_body() -> None:
    client = TestClient(
        create_app(
            Settings(
                jwt_secret="test-secret-with-at-least-thirty-two-bytes",
                max_request_body_bytes=1,
            )
        )
    )
    response = client.post(
        "/v1/auth/anonymous-session",
        content="{}",
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 413
