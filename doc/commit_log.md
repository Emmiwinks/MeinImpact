# Commit Log

This file records the intentional step-by-step commits used to bootstrap the
project structure. Future agents should keep commits similarly small and focused
when the user requests traceable commit history.

## Bootstrap Commits

- `0ec1ffa` - `Add project guidance and architecture docs`: repository rules,
  product concept, architecture, security baseline, CI/CD plan, issue plan, and
  the local identity placeholder rule.
- `1bd165a` - `Add FastAPI backend scaffold`: FastAPI backend, Dockerfile,
  Docker Compose with PostgreSQL, SSE endpoints, Mistral adapter abstraction,
  dummy repositories, security middleware, and backend tests.
- `497d749` - `Ignore generated Python package metadata`: removes generated
  `*.egg-info` files and prevents them from being committed again.
- `7c93c4a` - `Add Flutter app scaffold`: Flutter app core, API client, SSE
  parser, token storage abstraction, demo feed, domain models, and app tests.
- `fa15739` - `Add CI workflows and coverage tooling`: GitHub Actions for
  backend and app builds/tests plus LCOV coverage enforcement tooling.
- `869e3c6` - `Document bootstrap commits and issues`: records the bootstrap
  commit history and created GitHub issues in project documentation.
- `c45c201` - `Fix Flutter CI generated test and Linux deps`: removes the
  default generated Flutter widget test in CI and installs the Linux
  `libsecret-1` development dependency required by secure storage.

## Bootstrap Issues

- `#1` - Stream AI-assisted drafts through Mistral.
- `#2` - Add PostgreSQL migrations and repositories.
- `#3` - Implement transparent weekly recommendation scoring.
- `#4` - Implement onboarding and value profile storage.
- `#5` - Harden anonymous session authentication.
- `#6` - Integrate real civic and news source adapters.
- `#7` - Keep identity data local with draft placeholders.
- `#8` - Add secure token storage and API retry behavior.
- `#9` - Add action tracking and notification foundations.
- `#10` - Build initial Flutter action feed and draft flow.
- `#11` - Complete release packaging and security hardening.
