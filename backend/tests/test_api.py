"""API route tests."""

from uuid import uuid4

from fastapi.testclient import TestClient

from meinimpact.api.dependencies import get_action_repository
from meinimpact.core.config import Settings
from meinimpact.infrastructure.actions.dummy_action_repository import (
    DummyActionRepository,
)
from meinimpact.infrastructure.mdb.wks_service import MdbInfo, WksService
from meinimpact.main import create_app


def _mock_wks() -> WksService:
    svc = WksService()
    svc._index = {
        "10115": [
            MdbInfo(
                wahlkreis_nr=75,
                wahlkreis_name="Berlin-Mitte",
                mdb_name="Test Person",
                mdb_party="Test Partei",
                mdb_link=None,
            )
        ]
    }
    svc._load_error = None
    return svc


def _client() -> TestClient:
    settings = Settings(
        jwt_secret="test-secret",
        allowed_origins=["http://testserver"],
    )
    app = create_app(settings)
    app.dependency_overrides[get_action_repository] = DummyActionRepository
    # Inject mock WKS service so tests don't hit the Bundestag endpoint
    app.state.wks_service = _mock_wks()
    return TestClient(app)


def _auth_headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/v1/auth/anonymous-session",
        json={"installation_id": str(uuid4()), "app_version": "0.1.0"},
    )
    assert response.status_code == 201
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_health_has_security_headers() -> None:
    client = _client()
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["Cache-Control"] == "no-store"


def test_protected_route_requires_bearer_token() -> None:
    client = _client()
    response = client.get("/v1/news")
    assert response.status_code == 401


def test_protected_route_rejects_invalid_bearer_token() -> None:
    client = _client()
    response = client.get(
        "/v1/news",
        headers={"Authorization": "Bearer invalid-token"},
    )
    assert response.status_code == 401


def test_news_route_returns_dummy_news() -> None:
    client = _client()
    response = client.get("/v1/news", headers=_auth_headers(client))
    assert response.status_code == 200
    assert response.json()["news"][0]["id"] == "committee-solar-access"


def test_recommendations_route_returns_explanations() -> None:
    client = _client()
    response = client.post(
        "/v1/actions/recommendations",
        headers=_auth_headers(client),
        json={
            "profile": {
                "topics": ["climate", "housing"],
                "value_axes": {"civil_rights": 2},
                "region": "Germany",
            },
            "limit": 2,
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["recommendations"]) == 2
    assert body["recommendations"][0]["score"] > 0
    assert body["recommendations"][0]["reasons"]


def test_action_route_returns_404_for_unknown_action() -> None:
    client = _client()
    response = client.get("/v1/actions/missing", headers=_auth_headers(client))
    assert response.status_code == 404


def test_action_route_returns_action() -> None:
    client = _client()
    response = client.get(
        "/v1/actions/solar-letter-bundestag",
        headers=_auth_headers(client),
    )
    assert response.status_code == 200
    assert response.json()["id"] == "solar-letter-bundestag"


def test_letter_stream_returns_404_for_unknown_action() -> None:
    client = _client()
    response = client.post(
        "/v1/letters/stream",
        headers=_auth_headers(client),
        json={
            "action_id": "missing-action",
            "type": "brief",
            "recipient_name": "Test MdB",
            "recipient_party": "Test",
            "tone_descriptors": ["balanced"],
        },
    )
    assert response.status_code == 404


def test_letter_stream_returns_raw_sse_tokens() -> None:
    client = _client()
    with client.stream(
        "POST",
        "/v1/letters/stream",
        headers=_auth_headers(client),
        json={
            "action_id": "solar-letter-bundestag",
            "type": "brief",
            "recipient_name": "Test MdB",
            "recipient_party": "Test",
            "tone_descriptors": ["balanced"],
            "lebenssituation": [],
        },
    ) as response:
        assert response.status_code == 200
        body = response.read().decode()
    assert "data: " in body
    assert "data: [DONE]" in body


def test_pool_route_returns_all_actions() -> None:
    client = _client()
    response = client.get("/v1/actions/pool", headers=_auth_headers(client))
    assert response.status_code == 200
    body = response.json()
    assert len(body["actions"]) == 3
    assert "version" in body
    assert body["actions"][0]["werte_relevanz"] == {}


def test_mdb_returns_result_for_known_plz() -> None:
    client = _client()
    response = client.get("/v1/mdb?plz=10115", headers=_auth_headers(client))
    assert response.status_code == 200
    body = response.json()
    assert body["plz"] == "10115"
    assert len(body["results"]) == 1
    assert body["results"][0]["mdb_name"] == "Test Person"
    assert body["results"][0]["wahlkreis_nr"] == 75


def test_mdb_returns_404_for_unknown_plz() -> None:
    client = _client()
    response = client.get("/v1/mdb?plz=99999", headers=_auth_headers(client))
    assert response.status_code == 404


def test_mdb_returns_400_for_invalid_plz() -> None:
    client = _client()
    response = client.get("/v1/mdb?plz=abc", headers=_auth_headers(client))
    assert response.status_code == 400


def test_ready_health_route() -> None:
    client = _client()
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
