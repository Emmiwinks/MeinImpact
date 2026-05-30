# Architecture

MeinImpact uses a Flutter client and a FastAPI backend. The backend is designed
to be horizontally scalable and stateless, with persistent state stored in
PostgreSQL.

## Repository Layout

- `backend`: FastAPI application, domain services, infrastructure adapters,
  Dockerfile, Docker Compose, and backend tests.
- `app`: Flutter application, API client, feature modules, and Flutter tests.
- `doc`: Product, architecture, security, and delivery documentation.
- `.github/workflows`: Continuous integration for backend and app.

## Backend Runtime

- Python 3.14.
- FastAPI for HTTP APIs and OpenAPI documentation.
- PostgreSQL for durable state.
- SQLAlchemy for database access.
- Mistral behind an AI provider interface.
- SSE over HTTPS for one-way token and status streams.

The backend must not keep user session state in memory. Access tokens are
validated locally. Refresh tokens, revocation state, action records, user
profiles, audit entries, and notification state belong in PostgreSQL when those
features are implemented.

## App Runtime

- Flutter for Android, iOS, web, Windows, macOS, and Linux.
- The app communicates only with the backend API.
- The app never contains Mistral credentials or database credentials.
- Sensitive tokens must use platform secure storage once authentication is
  implemented.
- Personal identity values that are only needed for external letters or emails,
  such as a real name, stay encrypted on the device whenever possible.

## Communication Model

- Regular API calls use JSON over HTTPS.
- Long-running AI draft generation uses HTTPS response streaming formatted as
  SSE.
- SSE events must be resumable or idempotent where practical.
- API responses must use semantic HTTP status codes and typed response schemas.

## Local Identity Placeholders

The backend and AI provider should receive the minimum viable context needed to
draft an action. Real names, private addresses, and similar personal identity
values are not needed for recommendation scoring or draft generation in the
initial product design.

For generated representative letters, the app inserts stable placeholders such
as `{{USER_FULL_NAME}}` before sending text to the backend. The model works with
the placeholders. Only after the user reviews the final message and explicitly
chooses to send it through an external channel, the app replaces placeholders
with locally encrypted values on the device.

Any future feature that stores or processes those identity values server-side
must add a written architecture decision, a data retention rule, and a deletion
path before implementation.

## Backend Layers

- API routes translate HTTP requests into service calls.
- Domain entities represent civic actions, news items, profiles, and scores.
- Domain services implement recommendation and draft orchestration logic.
- Repository protocols define persistence boundaries.
- Infrastructure adapters implement databases, external news sources, and AI
  providers.

## Initial Data Strategy

News and civic actions use dummy data in the first iteration. Real integrations
for official sources, petitions, consultations, and local portals will be added
through repository adapters later.

## AI Provider Strategy

Mistral is the first AI provider. All AI access goes through a backend provider
interface so future providers can be added without changing app code or domain
services.

## Platform Generation Note

The committed Flutter source is the platform-independent app core. Platform
folders can be generated with:

```bash
flutter create --platforms=android,ios,web,windows,macos,linux app
```

CI also generates platform folders before building each target. Generated
platform folders should be committed later when app signing, icons, permissions,
and store metadata become product decisions.
