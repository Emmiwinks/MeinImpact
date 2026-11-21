"""API route tests."""

from fastapi.testclient import TestClient

from meinimpact.core.config import Settings
from meinimpact.infrastructure.mdb.wks_service import WksService
from meinimpact.main import create_app


def _client() -> TestClient:
    settings = Settings(
        jwt_secret="test-secret",
        allowed_origins=["http://testserver"],
    )
    app = create_app(settings)
    # No Bundestag data needed here; keeps tests off the network
    app.state.wks_service = WksService()
    return TestClient(app)


def test_health_has_security_headers() -> None:
    client = _client()
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["Cache-Control"] == "no-store"


def test_protected_route_requires_bearer_token() -> None:
    client = _client()
    response = client.post("/v1/location", json={"plz": "01067"})
    assert response.status_code == 401


def test_protected_route_rejects_invalid_bearer_token() -> None:
    client = _client()
    response = client.post(
        "/v1/location",
        json={"plz": "01067"},
        headers={"Authorization": "Bearer invalid-token"},
    )
    assert response.status_code == 401


def test_legacy_routes_are_gone() -> None:
    client = _client()
    for method, path in [
        ("GET", "/v1/mdb?plz=01067"),
        ("GET", "/v1/actions/pool"),
        ("GET", "/v1/news"),
        ("POST", "/v1/push/register"),
        ("POST", "/v1/feedback"),
        ("POST", "/v1/beta/activate"),
    ]:
        assert client.request(method, path).status_code == 404, path


def test_ready_health_route() -> None:
    client = _client()
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
