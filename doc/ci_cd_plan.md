# CI/CD Plan

GitHub Actions builds, tests, and packages the backend and app.

## Backend CI

Backend CI runs on pull requests and pushes to `main`.

It performs:

- Python 3.14 setup.
- Dependency installation with development extras.
- Ruff formatting check.
- Ruff linting.
- Mypy type checks.
- Pytest with at least 95% coverage.
- Docker image build.

PostgreSQL is available as a service in CI so integration tests can be added
without changing the workflow.

## App CI

App CI runs on pull requests and pushes to `main`.

It performs:

- Flutter SDK setup.
- Platform folder generation for the build target.
- Dependency installation.
- Dart formatting check.
- Flutter static analysis.
- Flutter tests with at least 95% coverage on the Linux test job.
- Android debug APK build.
- Web release build.
- Linux debug desktop build.
- Windows debug desktop build.
- macOS release build.
- iOS release build without code signing.

Build outputs are uploaded as artifacts. Store signing, notarization, and app
store release steps are intentionally deferred until product identity, signing
accounts, and release channels are finalized.
