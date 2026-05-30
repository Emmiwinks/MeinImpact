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

## Local App

Install Flutter and make sure `flutter` is on `PATH`. Then from `app`:

```bash
flutter create --platforms=android,ios,web,windows,macos,linux .
flutter pub get
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

Recommended commit order for this scaffold:

- Repository guidance and product documentation.
- Backend scaffold and backend tests.
- Flutter app scaffold and app tests.
- CI/CD workflows and coverage tooling.
- GitHub issue creation and issue-plan documentation updates.

Each commit message must be English, concise, and describe one coherent change.

The initial bootstrap commit history is recorded in `doc/commit_log.md`.
