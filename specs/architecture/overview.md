# Architecture Overview

## Purpose
Defines the technology stack, deployment targets, guiding principles, and
structural boundaries of the MeinImpact system. All other specs reference this
document for stack decisions and constraints.

---

## Decisions

- **Political profiles never leave the device.** Under GDPR Art. 9, political
  values are a special category. The eight value scores, selected topics,
  whitelist/blacklist, and local action history are stored exclusively in device
  storage (Hive). The backend never receives, stores, or logs them.

- **Feed scoring runs on the device.** The app downloads the full action pool
  (≤ 100 actions, ≤ 150 KB JSON) and scores it locally against the user profile.
  No personalisation happens server-side.

- **MVP uses guest mode only. No user accounts.** There are no usernames,
  passwords, or session tokens in the MVP. Beta access is unlocked by a
  one-time beta token delivered via invite link, stored locally on the device.
  Subscription tokens for future premium are architected but not active in MVP.
  A full account system with E2E-encrypted profile backup is a documented V2
  decision. See `user/authentication.md`.

- **Mistral is the only AI provider.** All AI calls go through a backend
  provider interface so future providers can be swapped without touching app
  code or domain services.

- **FastAPI (Python 3.12) is the backend framework.** Deployed with Gunicorn +
  Uvicorn workers for horizontal scaling. This decision is final. If ML
  components (e.g. ParlBERT) are added later, they run as a separate Python
  service alongside the main backend.

- **SSE for streaming, not WebSocket.** Letter draft generation streams tokens
  back to the app via HTTP Server-Sent Events. WebSocket is not used anywhere
  in the system.

- **Rate limiting and a hard daily budget protect API costs.** The backend
  enforces per-device limits on AI calls and a global daily spend ceiling.
  See `technical/rate-limiting.md`.

- **App requires an internet connection.** There is no offline mode. Exception:
  an action detail and its generated draft are cached in memory for the current
  session so the user can finish editing a letter without connectivity.

- **Minimum user age is 18.** Enforced by a checkbox declaration during
  onboarding. No technical age verification in MVP.

- **Primary platforms are Android and iOS.** Web is a secondary target.
  Desktop platforms (Windows, macOS, Linux) are not in scope.

- **All user-facing strings are localised.** No hardcoded text in UI code.
  German is the default and only locale in MVP; the i18n structure supports
  additional languages from day one.

- **Accessibility is a first-class requirement.** Screenreader support (Flutter
  Semantics), scalable text, and high-contrast mode are required in every
  feature with a UI component. See `technical/accessibility.md`.

---

## Stack

| Layer | Technology | Notes |
|---|---|---|
| Mobile frontend | Flutter (Dart) | Android + iOS primary, Web secondary |
| Local storage | Hive | Profile, gamification, session cache |
| Backend | FastAPI (Python 3.12) | Gunicorn + Uvicorn workers, Fly.io EU |
| Database | PostgreSQL via Supabase | Managed, EU region (Frankfurt) |
| AI provider | Mistral API | mistral-small for classification, mistral-medium for letters |
| Web search | Tavily API | Background context per action |
| News feed | NewsData.io (free tier) | German politics filter |
| Streaming | HTTP SSE | Letter draft token stream |
| Push notifications | FCM + APNS via anonymous push token | No profile data in payload |
| Payments (V2) | Apple StoreKit 2, Google Play Billing, Stripe | Not active in MVP |
| Backend hosting | Fly.io (EU region) | GDPR: data stays in EU |
| Frontend hosting | Cloudflare Pages | Web build |
| Error tracking | Sentry (free tier) | Backend + Flutter |
| Monitoring | Fly.io Metrics + Supabase Dashboard + provider dashboards | See `technical/monitoring.md` |

---

## Repository Layout

```
meinimpact/
├── app/                        Flutter application
│   ├── lib/
│   │   ├── features/           Feature modules (feed, onboarding, letter, ...)
│   │   ├── core/               Shared services, routing, theming
│   │   ├── data/               API client, local storage adapters
│   │   └── l10n/               Localisation files
│   └── test/
├── backend/                    FastAPI application
│   ├── routers/                HTTP route handlers
│   ├── domain/                 Entities and domain services
│   ├── services/               AI, search, ingestion, push, budget
│   ├── repositories/           PostgreSQL adapters
│   ├── infrastructure/         External API adapters (Mistral, Tavily, ...)
│   └── tests/
├── specs/                      This specification tree
│   ├── architecture/
│   ├── user/
│   ├── data/
│   ├── features/
│   └── technical/
└── .github/workflows/          CI for backend and app
```

---

## Data Flow Overview

```
Device (Flutter app)
│
│  1. App opens → validate beta token locally → download action pool
│     (JSON, no profile sent to server)
│  2. Score pool locally against Hive profile
│  3. Display top 3–5 actions
│  4. User opens action → send action_id only
│     Backend generates "what this means for you" via Mistral
│     (profile never sent; text generated from action context only)
│  5. User requests letter draft → SSE stream from backend
│     Personal placeholders ({{USER_FULL_NAME}}) inserted by app before send
│     App replaces placeholders with locally stored values before final submit
│  6. User submits action → backend increments anonymous action counter
│
Backend (Fly.io)
│
│  Trigger-based ingestion pipeline (not scheduled — see
│  data/ingestion-pipeline.md "Status"): Tavily-search-based topic
│  discovery (replaces the retired DIP-sourced pipeline), full design
│  pending. Classify with Mistral (value axes, urgency, pro/contra).
│  Write to PostgreSQL action pool.
│
│  On tracking event:
│    Look up push_tokens subscribed to action_id
│    Send push notification (no profile data in payload)
```

---

## What the Backend Stores

The backend stores only the following. Nothing else is permitted without a
written architecture decision record.

```sql
-- Public action pool (no user data)
actions (id, title, werte_relevanz jsonb, urgency, engagement_state,
         state_reason, pipeline_source, deadline, source_url,
         pro_argumente[], contra_argumente[], tavily_context,
         active, created_at)

-- Beta access tokens (MVP only, no identity)
beta_tokens (token uuid, used boolean, created_at)

-- Anonymous push subscriptions (no profile, no identity)
push_subscriptions (push_token text, action_ids uuid[],
                    created_at timestamp)

-- Anonymous action counters (no user_id)
action_stats (action_id uuid, completion_count int, updated_at)

-- Tracking events (public civic data, no user reference)
tracking_events (action_id uuid, event_type text, description text,
                 occurred_at timestamp, source_url text)

-- Anonymous in-app feedback (no user_id, no device_id)
feedback (id uuid, action_id uuid, rating int,
          comment text, created_at timestamp)

-- API budget tracking (operational only, no user data)
api_spend (date date, provider text, tokens_used int, cost_eur numeric)
```

---

## What Stays on the Device

Everything that constitutes or could reconstruct a political profile.

Note: lebenssituation, sektor, wohnsituation, and plz_prefix are also sent
transiently to the backend in the context and letter generation flows. They
are never stored server-side. See `architecture/data-flow.md` boundary table.

```
Hive boxes:
  profile         value scores (8 integers), topics[], plz,
                  lebenssituation, wohnsituation, sektor,
                  whitelist[], blacklist[]
  gamification    streak, badges, completed_action_ids[], history[]
  session_cache   current action detail + draft (cleared on app restart)
  settings        language, font_size, high_contrast, notifications_enabled
  meta            schema_version, onboarding_completed,
                  min_age_confirmed, beta_token
```

---

## Authentication – MVP vs V2

### MVP: Guest mode with beta token
No accounts. No login. The invite link delivers a UUID beta token that is
stored locally and sent with every API request as a bearer token. The backend
validates it exists in the `beta_tokens` table. No identity is derived from it.

### V2: Account system with E2E-encrypted profile backup
When premium subscriptions and cross-device sync are introduced:
- Account created with email + password or magic link
- Encryption key derived client-side from password (Argon2), never sent to server
- Political profile encrypted with AES-256 on device before upload
- Server stores opaque encrypted blob — cannot read profile content
- On new device: login → derive key → decrypt profile locally

This decision is documented here but not implemented in MVP.

---

## Personal Identity Placeholders

The app inserts stable placeholders before sending any text to the backend or
to AI providers. The model works with placeholders. The app replaces them with
locally stored values only after the user explicitly triggers sending.

```
{{USER_FULL_NAME}}
{{USER_ADDRESS}}
{{USER_CITY}}
```

Any future feature that sends real identity values to the backend requires:
- A written architecture decision record in `specs/architecture/`
- A data retention rule
- A deletion path

---

## Backend Layers

| Layer | Responsibility |
|---|---|
| Routers | Translate HTTP into service calls; validate request shape |
| Domain entities | Action, NewsItem, BetaToken, TrackingEvent |
| Domain services | Feed assembly, draft orchestration, ingestion coordination |
| Repository protocols | Persistence boundaries (interface, not implementation) |
| Infrastructure adapters | PostgreSQL, Mistral, Tavily, NewsData.io, FCM/APNS |

---

## FastAPI Backend Runtime

- Python 3.12
- FastAPI for HTTP APIs and OpenAPI documentation
- Gunicorn process manager with Uvicorn async workers
- PostgreSQL via SQLAlchemy (async) + Alembic for migrations
- Mistral behind the AI provider interface
- SSE over HTTPS for letter draft streaming
- APScheduler for daily ingestion cronjob
- Redis (Fly.io managed) for rate limiting counters and session cache

The backend is stateless between requests. No user session state is kept in
memory. Rate limiting state and the action pool cache live in Redis.

---

## Schema Versioning (Local Hive)

Every change to a Hive box schema increments `meta.schema_version`. On app
start, the app runs the migration chain from the stored version to the current
version before rendering any UI. Migration functions are additive only —
existing keys are never deleted without explicit user confirmation.

---

## AI Provider Interface

All AI calls in the backend go through a single provider interface:

```python
class AIProvider(Protocol):
    async def classify_action(self, text: str) -> ActionClassification: ...
    async def generate_context(self, action: Action) -> str: ...
    async def stream_letter(
        self, action: Action, context: str
    ) -> AsyncIterator[str]: ...
```

Mistral is the first and currently only implementation. Switching providers
requires only a new adapter class implementing this interface.

---

## Dependencies

- Reads: nothing (this is the root spec)
- Referenced by: all other specs

---

## Open Questions

- None at architecture level. All decisions are final for MVP.
