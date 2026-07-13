# Development Workflow

## Local Backend

From `backend`:

```bash
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
uvicorn meinimpact.main:app --reload
```

Docker Compose starts PostgreSQL and the API:

```bash
docker compose -f backend/compose.yaml up --build
```

Apply backend database migrations from `backend`:

```bash
python -m alembic upgrade head
```

## Local App

Install Flutter and make sure `flutter` is on `PATH`. Then from `app`:

```bash
flutter create --platforms=android,ios,web,windows,macos,linux .
flutter pub get
flutter gen-l10n
flutter run
```

On this workstation Android Studio is the intended Android test environment.

## Quality Gates

Backend:

```bash
cd backend
ruff format --check .
ruff check .
mypy src tests
pytest --cov=meinimpact --cov-report=term-missing --cov-fail-under=95
```

App:

```bash
cd app
flutter gen-l10n
dart format --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --coverage
python ../tools/check_lcov.py coverage/lcov.info 95
```

## Issue-Driven Development

Use GitHub issues for detailed implementation work. Every issue should include:

- Goal.
- Scope.
- Acceptance criteria.
- Security considerations.
- Test expectations.

## Commit Workflow

When step-by-step commits are requested, use small commit groups and push each
commit before starting the next group.

Each commit message must be English, concise, and describe one coherent change.
