# Agent Guidelines

These rules apply to all human and automated contributors working on
MeinImpact.

## Language

- Write all documentation, code, comments, identifiers, issue bodies, pull
  request descriptions, and commit messages in English.
- User-facing product copy may be localized later, but source strings must keep
  a clear English source of truth until localization is implemented.

## Product Principles

- MeinImpact recommends civic actions; it must not tell users what to think.
- Every recommendation must expose understandable scoring reasons.
- Do not introduce political side-taking, hidden ranking factors, or opaque
  persuasion mechanics.
- Minimize collected data. Treat political preferences, location, demographics,
  and action history as sensitive data.
- Do not send real names, addresses, or other locally resolvable letter identity
  data to the backend or AI provider unless a documented feature explicitly
  requires server-side processing.
- Use placeholders for sensitive local identity values in generated drafts. The
  app replaces placeholders with locally encrypted values only immediately before
  the user sends an external message.
- Never put AI provider secrets, database credentials, signing keys, or private
  API keys into the Flutter app or the repository.

## Architecture Rules

- Keep `backend` and `app` independent. Shared contracts belong in documented
  API schemas, not in cross-folder imports.
- Backend processes must stay stateless. Store durable state in PostgreSQL and
  use managed external services for queues, rate limits, and object storage when
  needed.
- Use HTTPS in every deployed environment. Local HTTP is allowed only for local
  development.
- Use Server-Sent Events or HTTP response streaming for one-way server streams.
  Do not introduce WebSockets without a written architecture decision.
- Keep Mistral access behind backend interfaces so the AI provider can be
  replaced.

## Coding Standards

- Follow the Google Python Style Guide for backend code and Effective Dart for
  Flutter code.
- Prefer small cohesive files, explicit interfaces, and dependency injection at
  boundaries.
- Prefer typed public APIs and avoid untyped dictionaries crossing module
  boundaries.
- Keep functions short enough to understand without scrolling through unrelated
  concerns.
- Add comments only when they explain intent, security tradeoffs, or non-obvious
  behavior.

## Testing and Quality Gates

- Maintain at least 95% unit test coverage for backend and app code.
- Every behavioral change needs tests at the lowest useful level.
- Backend changes must pass `ruff`, `mypy`, and `pytest`.
- Flutter changes must pass `dart format`, `flutter analyze`, and
  `flutter test`.
- Do not lower quality gates to make a build pass.

## Security Rules

- Assume the client can be modified, replayed, automated, or reverse engineered.
- Enforce authorization and workflow state transitions on the backend.
- Validate all inputs at API boundaries with strict schemas and bounded lengths.
- Do not log secrets, access tokens, refresh tokens, political profiles, or full
  generated drafts.
- Use generic external error messages and detailed internal logs with request
  IDs.
- Add abuse prevention before enabling costly AI or outbound API calls in
  production.

## GitHub Workflow

- Use GitHub issues for detailed development tasks.
- Keep issue descriptions actionable with acceptance criteria and test
  expectations.
- Prefer small pull requests that can be reviewed independently.
- Do not commit generated secrets, local build outputs, or machine-specific
  files.
- Use small, targeted commits. Each commit should add one coherent capability or
  documentation slice and must be pushed before starting the next commit group
  when the user requests step-by-step commits.
