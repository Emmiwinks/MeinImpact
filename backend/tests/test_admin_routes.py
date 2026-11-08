"""Tests for the admin ingestion-trigger route and the /admin page."""

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from meinimpact.api.dependencies import get_ingestion_runs
from meinimpact.api.routes import admin_portal
from meinimpact.core.config import Settings
from meinimpact.infrastructure.pipeline.run_repository import RunRecord, Schedule
from meinimpact.main import create_app
from meinimpact.services.ingestion_runs import Overview

_HEADERS = {"X-Admin-Api-Key": "secret"}


class FakeRuns:
    def __init__(self, *, claimable: bool = True) -> None:
        self.claimable = claimable
        self.claimed: list[str] = []
        self.executed: list[int] = []
        self.schedule = Schedule(enabled=True, interval_hours=48)
        self.runs: list[RunRecord] = []

    async def claim(self, trigger: str) -> int | None:
        if not self.claimable:
            return None
        self.claimed.append(trigger)
        return 7

    async def execute(self, run_id: int) -> None:
        self.executed.append(run_id)

    async def overview(self) -> Overview:
        return Overview(schedule=self.schedule, runs=self.runs)

    async def set_schedule(self, schedule: Schedule) -> None:
        self.schedule = schedule


@pytest.fixture(autouse=True)
def _reset_throttle() -> None:
    admin_portal._failures.clear()


def _client(
    runs: FakeRuns | None = None,
    *,
    admin_api_key: str | None = "secret",
    admin_password: str | None = "pw",
    mistral_api_key: str | None = "key",
) -> TestClient:
    settings = Settings(
        admin_api_key=admin_api_key,
        admin_password=admin_password,
        mistral_api_key=mistral_api_key,
    )
    app = create_app(settings)
    fake = runs or FakeRuns()
    app.dependency_overrides[get_ingestion_runs] = lambda: fake
    return TestClient(app, follow_redirects=False)


def _signed_in(runs: FakeRuns | None = None, **kwargs: str | None) -> TestClient:
    client = _client(runs, **kwargs)
    response = client.post("/admin/login", data={"password": "pw"})
    assert response.status_code == 303
    return client


# --- header-key API -------------------------------------------------------


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
    runs = FakeRuns()
    response = _client(runs).post("/v1/admin/ingestion/run", headers=_HEADERS)

    assert response.status_code == 202
    assert response.json() == {"status": "started"}
    assert runs.claimed == ["manual"]
    assert runs.executed == [7]


def test_concurrent_run_is_rejected() -> None:
    runs = FakeRuns(claimable=False)
    response = _client(runs).post("/v1/admin/ingestion/run", headers=_HEADERS)

    assert response.status_code == 409
    assert runs.executed == []


# --- /admin page ------------------------------------------------------------


def test_dashboard_redirects_to_login_without_session() -> None:
    response = _client().get("/admin")
    assert response.status_code == 303
    assert response.headers["location"] == "/admin/login"


def test_login_form_renders_with_own_csp() -> None:
    response = _client().get("/admin/login")
    assert response.status_code == 200
    assert 'name="password"' in response.text
    assert "style-src 'unsafe-inline'" in response.headers["content-security-policy"]


def test_wrong_password_is_rejected() -> None:
    response = _client().post("/admin/login", data={"password": "nope"})
    assert response.status_code == 401
    assert "mi_admin" not in response.cookies


def test_unconfigured_password_rejects_every_login() -> None:
    response = _client(admin_password=None).post("/admin/login", data={"password": ""})
    assert response.status_code == 401


def test_repeated_failures_are_throttled() -> None:
    client = _client()
    for _ in range(5):
        client.post("/admin/login", data={"password": "nope"})
    response = client.post("/admin/login", data={"password": "pw"})
    assert response.status_code == 429


def test_session_cookie_is_locked_down() -> None:
    response = _client().post("/admin/login", data={"password": "pw"})
    cookie = response.headers["set-cookie"].lower()
    assert "httponly" in cookie
    assert "samesite=strict" in cookie
    assert "path=/admin" in cookie


def test_app_token_is_not_an_admin_session() -> None:
    client = _client()
    token = client.post(
        "/v1/auth/anonymous-session",
        json={
            "installation_id": "5f0c7f0e-1b2c-4d5e-8f90-1234567890ab",
            "app_version": "1",
        },
    ).json()["access_token"]
    client.cookies.set("mi_admin", token, path="/admin")
    assert client.get("/admin").status_code == 303


def test_changed_password_ends_existing_sessions() -> None:
    client = _signed_in()
    cookie = client.cookies.get("mi_admin")
    other = _client(admin_password="new")
    other.cookies.set("mi_admin", cookie or "", path="/admin")
    assert other.get("/admin").status_code == 303


def test_dashboard_shows_runs_and_schedule() -> None:
    started = datetime(2026, 11, 8, 10, 0, tzinfo=UTC)
    runs = FakeRuns()
    runs.runs = [
        RunRecord(
            id=2,
            trigger="manual",
            status="failed",
            started_at=started,
            finished_at=started + timedelta(minutes=3),
            summary=None,
            error="RuntimeError: <boom>",
        ),
        RunRecord(
            id=1,
            trigger="scheduled",
            status="succeeded",
            started_at=started - timedelta(days=2),
            finished_at=started - timedelta(days=2) + timedelta(minutes=22),
            summary={
                "listed": 956,
                "kept": 241,
                "relevant": 85,
                "failed_sources": ["weact: timeout"],
                "errors": [],
            },
            error=None,
        ),
    ]

    page = _signed_in(runs).get("/admin").text

    assert "08.11.2026 11:00" in page  # Berlin time
    assert "RuntimeError: &lt;boom&gt;" in page
    assert "956 gelistet" in page
    assert "Quelle: weact: timeout" in page
    assert '<option value="48" selected>alle 2 Tage</option>' in page
    assert 'http-equiv="refresh"' not in page


def test_running_run_disables_button_and_refreshes() -> None:
    runs = FakeRuns()
    runs.runs = [
        RunRecord(
            id=3,
            trigger="manual",
            status="running",
            started_at=datetime.now(UTC),
            finished_at=None,
            summary=None,
            error=None,
        )
    ]
    page = _signed_in(runs).get("/admin").text
    assert "Jetzt ausführen</button>" in page
    assert "disabled" in page
    assert 'http-equiv="refresh"' in page


def test_run_button_starts_a_manual_run() -> None:
    runs = FakeRuns()
    response = _signed_in(runs).post("/admin/run")
    assert response.headers["location"] == "/admin?notice=started"
    assert runs.executed == [7]


def test_run_button_reports_busy() -> None:
    response = _signed_in(FakeRuns(claimable=False)).post("/admin/run")
    assert response.headers["location"] == "/admin?notice=busy"


def test_run_button_needs_mistral_key() -> None:
    runs = FakeRuns()
    response = _signed_in(runs, mistral_api_key=None).post("/admin/run")
    assert response.headers["location"] == "/admin?notice=no-mistral"
    assert runs.claimed == []


def test_run_button_needs_session() -> None:
    runs = FakeRuns()
    response = _client(runs).post("/admin/run")
    assert response.headers["location"] == "/admin/login"
    assert runs.claimed == []


def test_schedule_form_saves_choice() -> None:
    runs = FakeRuns()
    client = _signed_in(runs)
    response = client.post("/admin/schedule", data={"interval_hours": "24"})
    assert response.headers["location"] == "/admin?notice=saved"
    assert runs.schedule == Schedule(enabled=False, interval_hours=24)

    client.post("/admin/schedule", data={"enabled": "on", "interval_hours": "168"})
    assert runs.schedule == Schedule(enabled=True, interval_hours=168)


def test_schedule_form_ignores_unknown_interval() -> None:
    runs = FakeRuns()
    _signed_in(runs).post("/admin/schedule", data={"interval_hours": "1"})
    assert runs.schedule == Schedule(enabled=True, interval_hours=48)


def test_logout_clears_session() -> None:
    client = _signed_in()
    client.post("/admin/logout")
    assert client.get("/admin").status_code == 303
