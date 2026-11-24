# MeinImpact Backend

FastAPI backend for MeinImpact.

## Stack

- Python 3.14.
- FastAPI.
- PostgreSQL.
- SQLAlchemy with `asyncpg`.
- Mistral through an AI provider interface.
- HTTPS streaming with SSE payloads.

## Local Development

```bash
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
uvicorn meinimpact.main:app --reload
```

## Docker Compose

```bash
docker compose -f compose.yaml up --build
```

Apply database migrations against the configured PostgreSQL database:

```bash
python -m alembic upgrade head
```

## Monitoring

/admin shows every ingestion run with its Mistral cost, a row per source
(read, kept, enriched, cost, duration) and a coverage card per Land, Kreis
and Kommune. After each run, failed sources, sources that read far less
than in their own recent runs, and a reached budget become alerts
(`infrastructure/alerts.py`). Without Sentry they only go to the log.

To get them by mail:

1. Create a free account at sentry.io and a project of type "Python"
   ("FastAPI"). Under Alerts, keep the default rule that mails new issues.
2. Copy the project's DSN (Settings > Client Keys).
3. Set it on Fly: `fly secrets set MEINIMPACT_SENTRY_DSN=<dsn>`.

Sentry then also receives crashes. It never gets personal data: no IPs,
cookies, headers or request bodies.

What one run may spend on Mistral is `MEINIMPACT_INGESTION_MAX_COST_EUR`
(default 2.0). Listings left when it is reached are enriched by the next
run. Coverage thresholds live in `services/coverage.py`, drift thresholds
in `infrastructure/pipeline/drift.py`; both are provisional.

## Quality Gates

```bash
ruff format --check .
ruff check .
mypy src tests
pytest
```
