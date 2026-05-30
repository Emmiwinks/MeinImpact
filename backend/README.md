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

## Quality Gates

```bash
ruff format --check .
ruff check .
mypy src tests
pytest
```
