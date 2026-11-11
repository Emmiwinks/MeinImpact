"""The /admin page: start ingestion, set its schedule, see past runs.

Server-rendered HTML without JavaScript. Login is one password
(MEINIMPACT_ADMIN_PASSWORD); a correct one gets a signed session cookie that
is HttpOnly, SameSite=Strict (which also stops cross-site form posts) and
scoped to /admin. Failed logins are throttled per client IP.
"""

import hashlib
import secrets
import time
from collections import defaultdict, deque
from datetime import UTC, datetime, timedelta
from html import escape
from typing import Any
from urllib.parse import parse_qs
from zoneinfo import ZoneInfo

import jwt
from fastapi import APIRouter, BackgroundTasks, Depends, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response

from meinimpact.api.dependencies import get_ingestion_runs
from meinimpact.core.config import Settings, get_settings
from meinimpact.infrastructure.pipeline.run_repository import RunRecord, Schedule
from meinimpact.services.ingestion_runs import (
    INTERVAL_CHOICES_HOURS,
    IngestionRuns,
    Overview,
)

router = APIRouter(prefix="/admin", include_in_schema=False)

_COOKIE = "mi_admin"
_AUDIENCE = "meinimpact-admin"
_BERLIN = ZoneInfo("Europe/Berlin")
_MAX_FAILURES = 5
_FAILURE_WINDOW_SECONDS = 15 * 60
_failures: defaultdict[str, deque[float]] = defaultdict(deque)

_CSP = (
    "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; "
    "frame-ancestors 'none'; base-uri 'none'"
)
_INTERVAL_LABELS = {
    12: "alle 12 Stunden",
    24: "täglich",
    48: "alle 2 Tage",
    72: "alle 3 Tage",
    168: "wöchentlich",
}
_NOTICES = {
    "started": "Lauf gestartet.",
    "busy": "Es läuft schon ein Lauf.",
    "no-mistral": "MEINIMPACT_MISTRAL_API_KEY fehlt, Lauf nicht gestartet.",
    "saved": "Zeitplan gespeichert.",
}


@router.get("")
async def dashboard(
    request: Request,
    settings: Settings = Depends(get_settings),
    runs: IngestionRuns = Depends(get_ingestion_runs),
) -> Response:
    if not _signed_in(request, settings):
        return _redirect("/admin/login")
    overview = await runs.overview()
    notice = _NOTICES.get(request.query_params.get("notice", ""))
    return _page(
        "Ingestion",
        _dashboard_body(overview, settings, notice),
        refresh=overview.running is not None,
    )


@router.get("/login")
async def login_form() -> Response:
    return _page("Anmelden", _login_body(None))


@router.post("/login")
async def login(
    request: Request, settings: Settings = Depends(get_settings)
) -> Response:
    client = _client_ip(request)
    if _throttled(client):
        return _page(
            "Anmelden",
            _login_body("Zu viele Versuche. Bitte in 15 Minuten erneut."),
            status_code=429,
        )
    password = (await _form(request)).get("password", "")
    configured = settings.admin_password
    if not configured or not secrets.compare_digest(
        password.encode(), configured.encode()
    ):
        _failures[client].append(time.monotonic())
        return _page("Anmelden", _login_body("Falsches Passwort."), status_code=401)
    _failures.pop(client, None)
    response = _redirect("/admin")
    response.set_cookie(
        _COOKIE,
        _session_token(settings),
        max_age=settings.admin_session_hours * 3600,
        path="/admin",
        httponly=True,
        secure=settings.environment != "local",
        samesite="strict",
    )
    return response


@router.post("/logout")
async def logout() -> Response:
    response = _redirect("/admin/login")
    response.delete_cookie(_COOKIE, path="/admin")
    return response


@router.post("/run")
async def start_run(
    request: Request,
    background_tasks: BackgroundTasks,
    settings: Settings = Depends(get_settings),
    runs: IngestionRuns = Depends(get_ingestion_runs),
) -> Response:
    if not _signed_in(request, settings):
        return _redirect("/admin/login")
    if not settings.mistral_api_key:
        return _redirect("/admin?notice=no-mistral")
    run_id = await runs.claim("manual")
    if run_id is None:
        return _redirect("/admin?notice=busy")
    background_tasks.add_task(runs.execute, run_id)
    return _redirect("/admin?notice=started")


@router.post("/schedule")
async def save_schedule(
    request: Request,
    settings: Settings = Depends(get_settings),
    runs: IngestionRuns = Depends(get_ingestion_runs),
) -> Response:
    if not _signed_in(request, settings):
        return _redirect("/admin/login")
    form = await _form(request)
    try:
        interval = int(form.get("interval_hours", ""))
    except ValueError:
        interval = 0
    if interval not in INTERVAL_CHOICES_HOURS:
        return _redirect("/admin")
    await runs.set_schedule(
        Schedule(enabled=form.get("enabled") == "on", interval_hours=interval)
    )
    return _redirect("/admin?notice=saved")


def _session_token(settings: Settings) -> str:
    now = datetime.now(UTC)
    token = jwt.encode(
        {
            "sub": "admin",
            "aud": _AUDIENCE,
            "iat": now,
            "exp": now + timedelta(hours=settings.admin_session_hours),
        },
        _signing_key(settings),
        algorithm="HS256",
    )
    # The stubs allow bytes (PyJWT 1); see security/tokens.py
    return token.decode("utf-8") if isinstance(token, bytes) else token


def _signed_in(request: Request, settings: Settings) -> bool:
    token = request.cookies.get(_COOKIE)
    if not token or not settings.admin_password:
        return False
    try:
        jwt.decode(
            token, _signing_key(settings), algorithms=["HS256"], audience=_AUDIENCE
        )
    except jwt.PyJWTError:
        return False
    return True


def _signing_key(settings: Settings) -> str:
    # Mixing in the password means a leaked or default jwt_secret alone can't
    # forge a session, and changing the password signs everyone out.
    material = f"{settings.jwt_secret}\0{settings.admin_password}".encode()
    return hashlib.sha256(material).hexdigest()


def _client_ip(request: Request) -> str:
    # Fly's proxy puts the real client address here.
    forwarded = request.headers.get("fly-client-ip")
    if forwarded:
        return forwarded
    return request.client.host if request.client else "unknown"


def _throttled(client: str) -> bool:
    attempts = _failures[client]
    cutoff = time.monotonic() - _FAILURE_WINDOW_SECONDS
    while attempts and attempts[0] < cutoff:
        attempts.popleft()
    return len(attempts) >= _MAX_FAILURES


async def _form(request: Request) -> dict[str, str]:
    fields = parse_qs((await request.body()).decode(), keep_blank_values=True)
    return {key: values[0] for key, values in fields.items()}


def _redirect(url: str) -> Response:
    return RedirectResponse(url, status_code=303)


def _page(
    title: str, body: str, *, status_code: int = 200, refresh: bool = False
) -> Response:
    meta_refresh = '<meta http-equiv="refresh" content="20">' if refresh else ""
    html = f"""<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
{meta_refresh}
<title>{escape(title)} · MeinImpact Admin</title>
<style>{_STYLE}</style>
</head>
<body><main>{body}</main></body>
</html>"""
    return HTMLResponse(
        html, status_code=status_code, headers={"Content-Security-Policy": _CSP}
    )


def _login_body(error: str | None) -> str:
    message = f'<p class="error">{escape(error)}</p>' if error else ""
    return f"""
<h1>MeinImpact Admin</h1>
{message}
<form method="post" action="/admin/login" class="card">
  <label for="password">Passwort</label>
  <input id="password" name="password" type="password"
         autocomplete="current-password" required autofocus>
  <button type="submit">Anmelden</button>
</form>"""


def _dashboard_body(overview: Overview, settings: Settings, notice: str | None) -> str:
    running = overview.running
    parts = [
        """<header><h1>Ingestion</h1>
<form method="post" action="/admin/logout"><button class="link">Abmelden</button>
</form></header>"""
    ]
    if notice:
        parts.append(f'<p class="notice">{escape(notice)}</p>')
    if not settings.mistral_api_key:
        parts.append(
            '<p class="error">MEINIMPACT_MISTRAL_API_KEY ist nicht gesetzt.</p>'
        )

    if running:
        status_line = (
            f"Läuft seit {_time(running.started_at)} "
            f"({_TRIGGER_LABELS.get(running.trigger, running.trigger)}). "
            "Die Seite lädt sich alle 20 Sekunden neu."
        )
    else:
        status_line = "Gerade läuft nichts."
    disabled = " disabled" if running else ""
    parts.append(f"""
<section class="card">
  <h2>Jetzt</h2>
  <p>{status_line}</p>
  <form method="post" action="/admin/run">
    <button type="submit"{disabled}>Jetzt ausführen</button>
  </form>
</section>""")

    options = "".join(
        f'<option value="{hours}"'
        f"{' selected' if hours == overview.schedule.interval_hours else ''}>"
        f"{_INTERVAL_LABELS[hours]}</option>"
        for hours in INTERVAL_CHOICES_HOURS
    )
    checked = " checked" if overview.schedule.enabled else ""
    if not settings.ingestion_scheduler_enabled:
        next_line = (
            "Der Zeitplan ist auf diesem Server abgeschaltet "
            "(MEINIMPACT_INGESTION_SCHEDULER_ENABLED)."
        )
    elif overview.next_due is None:
        next_line = "Automatische Läufe sind aus."
    else:
        due = max(overview.next_due, datetime.now(UTC))
        next_line = (
            f"Nächster automatischer Lauf: ab {_time(due)} "
            f"(geprüft alle {settings.ingestion_check_minutes} Minuten)."
        )
    parts.append(f"""
<section class="card">
  <h2>Zeitplan</h2>
  <form method="post" action="/admin/schedule" class="row">
    <label class="check"><input type="checkbox" name="enabled"{checked}>
      Automatisch ausführen</label>
    <select name="interval_hours" aria-label="Intervall">{options}</select>
    <button type="submit">Speichern</button>
  </form>
  <p class="muted">{next_line} Ein manueller Lauf verschiebt den nächsten
  automatischen.</p>
</section>""")

    rows = "".join(_run_row(run) for run in overview.runs)
    parts.append(f"""
<section class="card">
  <h2>Letzte Läufe</h2>
  {f'<div class="runs">{rows}</div>' if rows else '<p class="muted">Noch keine.</p>'}
</section>""")
    return "".join(parts)


_TRIGGER_LABELS = {"scheduled": "automatisch", "manual": "manuell"}
_STATUS_LABELS = {
    "running": "läuft",
    "succeeded": "fertig",
    "failed": "fehlgeschlagen",
}
_SUMMARY_LABELS = (
    ("listed", "gelistet"),
    ("kept", "behalten"),
    ("inserted", "neu"),
    ("updated", "geändert"),
    ("deactivated", "deaktiviert"),
    ("enriched", "angereichert"),
    ("relevant", "relevant"),
    ("council_members", "Ratsmitglieder"),
)


def _run_row(run: RunRecord) -> str:
    duration = ""
    if run.finished_at:
        minutes = (run.finished_at - run.started_at).total_seconds() / 60
        duration = f" · {minutes:.0f} min"
    head = (
        f'<span class="status {run.status}">'
        f"{_STATUS_LABELS.get(run.status, run.status)}</span> "
        f"{_time(run.started_at)} · "
        f"{_TRIGGER_LABELS.get(run.trigger, run.trigger)}{duration}"
    )
    details: list[str] = []
    summary: dict[str, Any] = run.summary or {}
    if summary:
        counts = " · ".join(
            f"{summary.get(key, 0)} {label}" for key, label in _SUMMARY_LABELS
        )
        details.append(f'<p class="counts">{counts}</p>')
    problems = [
        *(f"Quelle: {item}" for item in summary.get("failed_sources", [])),
        *summary.get("errors", []),
    ]
    if run.error:
        details.append(f'<p class="error">{escape(run.error)}</p>')
    if problems:
        items = "".join(f"<li>{escape(str(item))}</li>" for item in problems)
        details.append(
            f"<details><summary>{len(problems)} Fehler einzelner Einträge"
            f"</summary><ul>{items}</ul></details>"
        )
    return f'<div class="run"><p>{head}</p>{"".join(details)}</div>'


def _time(moment: datetime) -> str:
    return moment.astimezone(_BERLIN).strftime("%d.%m.%Y %H:%M")


_STYLE = """
:root { --bg: #f6f5f2; --card: #fff; --text: #1d1d1b; --muted: #6b6a66;
  --line: #e2e0da; --accent: #1f5f4a; --ok: #1f7a4d; --bad: #b3261e;
  --run: #8a5a00; color-scheme: light dark; }
@media (prefers-color-scheme: dark) { :root { --bg: #161615; --card: #20201e;
  --text: #ecebe7; --muted: #a3a29c; --line: #34332f; --accent: #7cc4a6;
  --ok: #6fcf97; --bad: #f2867c; --run: #e6b450; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
  font: 16px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 760px; margin: 0 auto; padding: 24px 16px 48px; }
header { display: flex; justify-content: space-between; align-items: center; }
h1 { font-size: 1.5rem; margin: 0 0 16px; }
h2 { font-size: 1.05rem; margin: 0 0 8px; }
.card { background: var(--card); border: 1px solid var(--line);
  border-radius: 10px; padding: 16px; margin: 0 0 16px; }
form.card { display: grid; gap: 10px; max-width: 360px; }
.row { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; }
input[type=password], select { font: inherit; padding: 8px 10px;
  border: 1px solid var(--line); border-radius: 8px; background: var(--bg);
  color: var(--text); }
button { font: inherit; padding: 8px 14px; border: 0; border-radius: 8px;
  background: var(--accent); color: var(--card); cursor: pointer; }
button[disabled] { opacity: .5; cursor: default; }
button.link { background: none; color: var(--muted); padding: 0;
  text-decoration: underline; }
.check { display: flex; gap: 6px; align-items: center; }
.muted, .counts { color: var(--muted); font-size: .9rem; margin: 6px 0 0; }
.notice { border-left: 3px solid var(--accent); padding: 4px 10px; }
.error { color: var(--bad); }
.run { border-top: 1px solid var(--line); padding: 10px 0; }
.run:first-child { border-top: 0; padding-top: 0; }
.run p { margin: 0; }
.status { font-weight: 600; }
.status.succeeded { color: var(--ok); }
.status.failed { color: var(--bad); }
.status.running { color: var(--run); }
details { margin-top: 6px; font-size: .9rem; }
details li { overflow-wrap: anywhere; }
"""
