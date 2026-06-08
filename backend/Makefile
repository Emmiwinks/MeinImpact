.PHONY: build up down migrate start logs shell test lint deploy fly-logs fly-secrets fly-migrate

# ── Local Docker ─────────────────────────────────────────────────────────────

## Rebuild the image and (re)start all services, waiting until healthy
build:
	docker compose up --build -d --wait

## Start existing containers without rebuilding
up:
	docker compose up -d

## Stop all containers
down:
	docker compose down

## Run pending Alembic migrations inside the running container
migrate:
	docker compose exec api python -m alembic upgrade head

## Full local dev reset: rebuild image + run migrations
start: build migrate

## Follow API logs (Ctrl-C to exit)
logs:
	docker compose logs -f api

## Open a shell inside the running API container
shell:
	docker compose exec api bash

# ── Local tests & quality ─────────────────────────────────────────────────────

## Run the full test suite
test:
	pytest

## Check formatting and linting
lint:
	ruff format --check .
	ruff check .

# ── Production (Fly.io) ───────────────────────────────────────────────────────

## Deploy to Fly.io (migrations run automatically via release_command)
deploy:
	fly deploy

## Stream production logs
fly-logs:
	fly logs

## List production secrets (values hidden)
fly-secrets:
	fly secrets list

## Manually trigger migrations on the running production machine
fly-migrate:
	fly ssh console --pty -C "python -m alembic upgrade head"
