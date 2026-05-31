# Changelog

All notable changes to MeinImpact are tracked here. Each backend or app change
must bump the affected component version and add a short changelog entry before
commit.

Version sources:

- Backend: `backend/VERSION` and `backend/pyproject.toml`.
- App: `app/VERSION` and `app/pubspec.yaml`.

## 2026-05-30

### App 0.1.2+3

- Added bounded retry behavior for transient JSON API failures.
- Added generic network error mapping for JSON and SSE transport failures.
- Added API client tests for retry limits and token-safe error messages.

### App 0.1.1+2

- Added native Flutter localization support with English and German ARB files.
- Added an in-app language selector so users can switch freely between English
  and German.
- Added app version tracking through `app/VERSION`.
- Added app version consistency coverage for `app/VERSION` and `pubspec.yaml`.

### Backend 0.1.1

- Switched PostgreSQL connectivity from `psycopg` to `asyncpg`.
- Added Alembic migration tooling and an initial PostgreSQL schema migration.
- Added backend version tracking through `backend/VERSION`.
- Added backend version consistency coverage for `backend/VERSION` and
  `pyproject.toml`.

### App 0.1.0+1

- Added the initial Flutter app scaffold, feed UI, API client, SSE parser,
  secure token storage abstraction, tests, and CI builds.

### Backend 0.1.0

- Added the initial FastAPI backend scaffold with JWT authentication, dummy data
  repositories, recommendation endpoints, SSE draft streaming, Mistral provider
  abstraction, Docker Compose, tests, and CI.

### Repository

- Added project guidance, product concept, architecture, security, workflow, and
  CI/CD documentation.
- Added GitHub issue plan and initial issue tracking.
- Added the original concept PDF at `doc/papilio_in_kurz.pdf`.
