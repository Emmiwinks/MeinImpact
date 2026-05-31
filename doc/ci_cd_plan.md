# CI/CD Plan

GitHub Actions builds, tests, and packages the backend and app. GitLab CI also
validates and publishes the backend Docker image for registry-based deployment.

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
- GitLab Container Registry push for default branch and release tag backend
  images.

PostgreSQL is available as a service in CI so integration tests can be added
without changing the workflow.

Published GitLab backend images use `registry.gitlab.com/<group>/<project>/backend`
with the commit SHA tag on every published build. Default branch builds also get
the branch slug and `latest` tags. Git tag pipelines also publish the matching
tag name.

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
