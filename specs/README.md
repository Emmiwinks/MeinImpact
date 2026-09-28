# MeinImpact – Specification Index

This is the entry point for all specifications. Read this file first
before reading any other spec. All AI agents should start here.

---

## What MeinImpact Does

MeinImpact is a mobile-first civic engagement app that activates
politically interested but passive German citizens. Users receive
weekly personalised recommendations for civic actions (letters to
their MdB, petitions, public questions) and get follow-up
notifications about outcomes.

One-sentence value proposition:
**Weekly civic action, matched to your values, with real follow-up.**

---

## Critical Constraints (Read Before Everything Else)

1. **Political profiles (value scores, topics) never leave the device.**
   GDPR Art. 9. No exceptions. See `architecture/dsgvo.md`.

2. **Demographic fields (lebenssituation, sektor, PLZ prefix, wohnsituation)
   are sent transiently for AI generation. Never stored server-side.**
   See `architecture/dsgvo.md` Category D.

3. **FastAPI (Python 3.12) is the backend. This is final.**
   See `architecture/overview.md`.

4. **Flutter (Dart) is the frontend. Hive is local storage.**
   See `architecture/overview.md`.

5. **MVP uses beta tokens only. No user accounts.**
   See `user/authentication.md`.

6. **Three action types in MVP: brief, petition, anfrage.**
   No EU consultations, no Leserbriefe, no local/state actions.
   See `features/action-types.md`.

7. **Feed has no hardcoded maximum and no surprise slot.**
   All actions scoring ≥ 0.2 are shown. See `features/feed.md`.

---

## Spec Tree

```
specs/
├── README.md                      ← You are here
│
├── architecture/
│   ├── overview.md                ← Stack, repo layout, what backend stores
│   ├── dsgvo.md                   ← GDPR architecture, data categories A–D
│   └── data-flow.md               ← All 10 data flows, boundary table
│
├── user/
│   ├── authentication.md          ← Beta token MVP, E2E account V2
│   ├── onboarding.md              ← 6-screen flow, all questions defined
│   ├── value-profile.md           ← 8values model, scoring math, tone derivation
│   └── general-profile.md         ← Demographics, MdB lookup, letter context
│
├── data/
│   ├── sources-federal.md         ← AW, MdB statements; topic sourcing being
│   │                                 redesigned (Tavily search, was DIP)
│   ├── ingestion-pipeline.md      ← Trigger-based (was daily); pipeline being
│   │                                 redesigned, was DIP-sourced
│   ├── database-schema.md         ← All PostgreSQL tables + pool view
│   └── caching.md                 ← Redis server cache, Hive client cache
│
├── features/
│   ├── feed.md                    ← Scoring algorithm, assembly, display
│   ├── action-types.md            ← Brief, petition, anfrage flows
│   ├── letter-generation.md       ← Streaming, prompts, placeholders, fallback
│   ├── tracking.md                ← Tier 1 (DIP), Tier 2 (scraping+Tavily)
│   └── gamification.md            ← Streak, badges, activity screen
│
└── technical/
    ├── api-endpoints.md           ← All endpoints, request/response shapes
    ├── local-storage.md           ← Complete Hive schema, migration, export
    ├── streaming.md               ← SSE server + Flutter client
    ├── rate-limiting.md           ← Per-device limits, global budget ceiling
    ├── monitoring.md              ← Sentry, Fly.io, cost queries, alerts
    └── accessibility.md           ← WCAG AA, semantics, contrast, motion
```

---

## Technology Stack (Final Decisions)

| Layer | Technology |
|---|---|
| Mobile frontend | Flutter (Dart) — Android + iOS primary, Web secondary |
| Local storage | Hive — all profile and gamification data |
| Backend | FastAPI (Python 3.12) — Gunicorn + Uvicorn |
| Database | PostgreSQL via Supabase (EU region, Frankfurt) |
| Cache | Redis via Fly.io managed |
| AI | Mistral API (mistral-small for classification, mistral-medium for letters) |
| Web search | Tavily API |
| News | NewsData.io (free tier) |
| Streaming | HTTP SSE — not WebSocket |
| Push | FCM (Android) + APNS (iOS) — anonymous tokens only |
| Payments | Not active in MVP |
| Backend hosting | Fly.io (EU — Frankfurt) |
| Frontend hosting | Cloudflare Pages |
| Errors | Sentry (free tier) |

---

## Data Stored on Backend (Complete List)

The backend stores ONLY these tables. Nothing else.

| Table | Contains |
|---|---|
| `actions` | Public civic action pool — no user data |
| `beta_tokens` | Anonymous UUIDs — no identity |
| `push_subscriptions` | Anonymous device push tokens |
| `action_stats` | Anonymous completion counters |
| `tracking_events` | Public civic outcome data |
| `mdb_statements` | MdB public statement search results |
| `feedback` | Anonymous ratings and comments |
| `api_spend` | Cost tracking — no user data |
| `pipeline_runs` | Ingestion run logs — no user data |

---

## Data Stored on Device (Complete List)

| Hive box | Contains |
|---|---|
| `auth` | Beta token — never deleted by user reset |
| `meta` | App state, schema version, onboarding status |
| `profile` | Value scores, topics, demographics, MdB cache |
| `gamification` | Streak, badges, action history |
| `settings` | Language, font size, contrast, notifications |
| `pool_cache` | Cached action pool JSON |
| `session_cache` | Current action + draft (session only) |

---

## Key Design Decisions Log

| Decision | Rationale | Spec |
|---|---|---|
| Profile stays on device | GDPR Art. 9 — political beliefs | dsgvo.md |
| FastAPI over Node | Python for AI ecosystem compatibility | overview.md |
| SSE over WebSocket | One-way stream, simpler, stateless | streaming.md |
| No user accounts in MVP | Reduces complexity, GDPR clean | authentication.md |
| Demographic fields sent transiently | Enables real personalisation without Art. 9 issues | dsgvo.md |
| No EU consultations | Aufwand-Nutzen not justified for MVP | sources-federal.md |
| No max feed size | All relevant actions shown above threshold | feed.md |
| No surprise slot | Simplifies feed logic, V2 feature | feed.md |
| MdB statements explicit not-found | Honest communication over false impressions | tracking.md |
| Beta tokens not logged | GDPR — token = de-facto identifier | api-endpoints.md |

---

## Reading Order for AI Agents

When implementing a specific feature, read specs in this order:

1. This README
2. `architecture/overview.md`
3. `architecture/dsgvo.md`
4. `architecture/data-flow.md`
5. The specific `features/` spec for what you are building
6. Referenced `user/`, `data/`, and `technical/` specs

When implementing backend endpoints:
1. `technical/api-endpoints.md`
2. `data/database-schema.md`
3. `technical/rate-limiting.md`

When implementing Flutter UI:
1. `technical/local-storage.md`
2. `technical/accessibility.md`
3. The relevant `features/` spec
