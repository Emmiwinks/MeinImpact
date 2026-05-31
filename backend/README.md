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

## GitLab Registry Image

GitLab CI builds the backend image as `registry.gitlab.com/<group>/<project>/backend`.
Default branch builds are pushed with the commit SHA, branch slug, and `latest` tags.
Git tags are also pushed as matching image tags.

Deploy the published image without rebuilding it locally:

```bash
docker login registry.gitlab.com
docker compose -f compose.deploy.yaml up -d
```

Set these runtime values through environment variables or a local `.env` file on
the deployment host:

```bash
MEINIMPACT_BACKEND_IMAGE=registry.gitlab.com/<group>/<project>/backend:latest
MEINIMPACT_DATABASE_URL=postgresql+asyncpg://user:password@postgres.example.com:5432/meinimpact
MEINIMPACT_JWT_SECRET=change-me
MEINIMPACT_MISTRAL_API_KEY=change-me
MEINIMPACT_ALLOWED_ORIGINS=["https://app.example.com"]
```

Run migrations with the same published image and runtime environment:

```bash
docker compose -f compose.deploy.yaml run --rm api python -m alembic upgrade head
```

For local Python setup, apply database migrations against the configured
PostgreSQL database:

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
