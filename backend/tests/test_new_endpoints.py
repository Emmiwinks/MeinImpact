"""Tests for new API endpoints added in spec implementation."""

from datetime import UTC, datetime
from uuid import uuid4

from fastapi.testclient import TestClient

from meinimpact.api.dependencies import (
    get_action_repository,
    get_action_stats_repository,
    get_beta_repository,
    get_feedback_repository,
    get_push_repository,
    get_tracking_repository,
)
from meinimpact.core.config import Settings
from meinimpact.domain.entities import MdbStatement, TrackingEvent
from meinimpact.infrastructure.actions.dummy_action_repository import (
    DummyActionRepository,
)
from meinimpact.infrastructure.mdb.wks_service import MdbInfo, WksService
from meinimpact.main import create_app

# ── Stubs ─────────────────────────────────────────────────────────────────────


class StubStatsRepository:
    def __init__(self) -> None:
        self.counts: dict[str, int] = {}

    async def increment_completion(self, action_id: str) -> int:
        self.counts[action_id] = self.counts.get(action_id, 0) + 1
        return self.counts[action_id]


class StubTrackingRepository:
    async def list_events(self, action_id: str) -> list[TrackingEvent]:
        return [
            TrackingEvent(
                id=uuid4(),
                action_id=action_id,
                event_type="vote_result",
                title="Abstimmung: Angenommen",
                description="Das Gesetz wurde angenommen.",
                outcome="positive",
                source_url="https://example.com",
                occurred_at=datetime(2026, 6, 18, 14, 0, tzinfo=UTC),
            )
        ]

    async def list_mdb_statements(self, action_id: str) -> list[MdbStatement]:
        return [
            MdbStatement(
                mdb_name="Sarah Müller",
                found=True,
                statement_summary="Müller begrüßt den Beschluss.",
                source_url="https://example.com",
                searched_at=datetime(2026, 6, 18, 3, 0, tzinfo=UTC),
            )
        ]


class StubPushRepository:
    def __init__(self) -> None:
        self.registrations: list[tuple[str, str]] = []
        self.subscriptions: list[tuple[str, str]] = []
        self.unsubscriptions: list[tuple[str, str]] = []

    async def register(self, push_token: str, platform: str) -> None:
        self.registrations.append((push_token, platform))

    async def subscribe(self, push_token: str, action_id: str) -> None:
        self.subscriptions.append((push_token, action_id))

    async def unsubscribe(self, push_token: str, action_id: str) -> None:
        self.unsubscriptions.append((push_token, action_id))


class StubFeedbackRepository:
    def __init__(self) -> None:
        self.entries: list[dict] = []

    async def submit(
        self,
        action_id: str | None,
        rating: int | None,
        comment: str | None,
    ) -> None:
        self.entries.append(
            {"action_id": action_id, "rating": rating, "comment": comment}
        )


class StubBetaRepository:
    def __init__(self, valid: bool = True) -> None:
        self._valid = valid

    async def activate(self, token: str) -> bool:
        return self._valid


_stats_stub = StubStatsRepository()
_tracking_stub = StubTrackingRepository()
_push_stub = StubPushRepository()
_feedback_stub = StubFeedbackRepository()
_beta_valid_stub = StubBetaRepository(valid=True)
_beta_invalid_stub = StubBetaRepository(valid=False)


# ── Client factory ────────────────────────────────────────────────────────────


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


def _client(beta_valid: bool = True) -> TestClient:
    settings = Settings(
        jwt_secret="test-secret",
        allowed_origins=["http://testserver"],
    )
    app = create_app(settings)
    app.dependency_overrides[get_action_repository] = DummyActionRepository
    app.dependency_overrides[get_action_stats_repository] = lambda: _stats_stub
    app.dependency_overrides[get_tracking_repository] = lambda: _tracking_stub
    app.dependency_overrides[get_push_repository] = lambda: _push_stub
    app.dependency_overrides[get_feedback_repository] = lambda: _feedback_stub
    app.dependency_overrides[get_beta_repository] = lambda: (
        _beta_valid_stub if beta_valid else _beta_invalid_stub
    )
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


# ── Health ────────────────────────────────────────────────────────────────────


def test_health_root_includes_pool_version() -> None:
    client = _client()
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["pool_version"] is not None
    assert body["app_version_min"] == "1.0.0"


# ── Action pool: new fields ───────────────────────────────────────────────────


def test_pool_response_includes_spec_fields() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.get("/v1/actions/pool", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert "generated_at" in body
    item = body["actions"][0]
    assert "pro_argumente" in item
    assert "contra_argumente" in item
    assert "action_types" in item
    assert "is_controversial" in item
    assert "position_required" in item
    assert "momentum_score" in item


# ── Action complete ───────────────────────────────────────────────────────────


def test_action_complete_returns_count() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/actions/solar-letter-bundestag/complete",
        headers=headers,
        json={"action_type": "brief"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["completion_count"] >= 1


def test_action_complete_returns_404_for_unknown() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/actions/does-not-exist/complete",
        headers=headers,
        json={"action_type": "brief"},
    )
    assert response.status_code == 404


def test_action_complete_rejects_invalid_type() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/actions/solar-letter-bundestag/complete",
        headers=headers,
        json={"action_type": "invalid"},
    )
    assert response.status_code == 422


# ── Action tracking ───────────────────────────────────────────────────────────


def test_action_tracking_returns_events_and_statements() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.get(
        "/v1/actions/solar-letter-bundestag/tracking",
        headers=headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["action_id"] == "solar-letter-bundestag"
    assert len(body["events"]) == 1
    assert body["events"][0]["event_type"] == "vote_result"
    assert len(body["mdb_statements"]) == 1
    assert body["mdb_statements"][0]["mdb_name"] == "Sarah Müller"
    assert body["mdb_statements"][0]["found"] is True


def test_action_tracking_returns_404_for_unknown() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.get("/v1/actions/unknown-action/tracking", headers=headers)
    assert response.status_code == 404


# ── Push ──────────────────────────────────────────────────────────────────────


def test_push_register_returns_ok() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/push/register",
        headers=headers,
        json={"push_token": "device-token-abc", "platform": "fcm"},
    )
    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_push_register_rejects_invalid_platform() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/push/register",
        headers=headers,
        json={"push_token": "device-token-abc", "platform": "sms"},
    )
    assert response.status_code == 422


def test_push_subscribe_returns_ok() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/push/subscribe",
        headers=headers,
        json={"push_token": "device-token-abc", "action_id": "solar-letter-bundestag"},
    )
    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_push_unsubscribe_returns_ok() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/push/unsubscribe",
        headers=headers,
        json={"push_token": "device-token-abc", "action_id": "solar-letter-bundestag"},
    )
    assert response.status_code == 200
    assert response.json()["ok"] is True


# ── Feedback ──────────────────────────────────────────────────────────────────


def test_feedback_returns_ok() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/feedback",
        headers=headers,
        json={"action_id": "solar-letter-bundestag", "rating": 4, "comment": "Gut!"},
    )
    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_feedback_without_action_id() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/feedback",
        headers=headers,
        json={"rating": 5},
    )
    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_feedback_rejects_out_of_range_rating() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/feedback",
        headers=headers,
        json={"rating": 6},
    )
    assert response.status_code == 422


def test_feedback_rejects_comment_over_500_chars() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/feedback",
        headers=headers,
        json={"comment": "x" * 501},
    )
    assert response.status_code == 422


# ── Beta token ────────────────────────────────────────────────────────────────


def test_beta_activate_valid_token() -> None:
    client = _client(beta_valid=True)
    response = client.post(
        "/v1/beta/activate",
        json={"token": "00000000-0000-0000-0000-000000000001"},
    )
    assert response.status_code == 200
    assert response.json()["valid"] is True


def test_beta_activate_invalid_token() -> None:
    client = _client(beta_valid=False)
    response = client.post(
        "/v1/beta/activate",
        json={"token": "00000000-0000-0000-0000-999999999999"},
    )
    assert response.status_code == 404


def test_beta_activate_requires_no_auth() -> None:
    """Beta activation must not require a bearer token."""
    client = _client()
    response = client.post(
        "/v1/beta/activate",
        json={"token": "00000000-0000-0000-0000-000000000001"},
    )
    assert response.status_code == 200


# ── Action context ────────────────────────────────────────────────────────────


def test_action_context_returns_text_for_known_action() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/actions/solar-letter-bundestag/context",
        headers=headers,
        json={"lebenssituation": ["elternteil"], "plz_prefix": "1"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["action_id"] == "solar-letter-bundestag"
    assert isinstance(body["context"], str)
    assert len(body["context"]) > 0


def test_action_context_returns_404_for_unknown_action() -> None:
    client = _client()
    headers = _auth_headers(client)
    response = client.post(
        "/v1/actions/does-not-exist/context",
        headers=headers,
        json={},
    )
    assert response.status_code == 404
