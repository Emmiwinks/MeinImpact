# Database Schema

## Purpose
Lists the PostgreSQL tables the backend keeps, what each is for, and its
retention. Column-level truth lives in the Alembic migrations
(`backend/migrations/versions/`) and the SQLAlchemy models
(`backend/src/meinimpact/infrastructure/models.py`); this file does not
repeat column lists. Rewritten 2026-11-24 after the retired action stack's
tables were dropped (migration 202611240026).

---

## Decisions

- **No user identity in any table.** No name, email, IP address,
  installation id or device fingerprint. Beta feedback carries only a keyed
  hash of the installation id. See `architecture/dsgvo.md`.
- **Migrations are the schema.** One migration per change, named
  `{date}_{number}_{short_description}.py`. Fly runs `alembic upgrade head`
  as the release command on every deploy. Drops of retired tables are
  one-way (`downgrade` raises).
- **Supabase, Frankfurt (EU).** Confirmed 2026-11-21.

---

## Tables

### Public data

| Table | Contents | Retention |
|---|---|---|
| `opportunities` | One participation opportunity read from a registry or OParl, plus its Mistral enrichment (framing, tags, Lebenslagen, Werte, reach, places, bundle). `tracked_since` is the only trace of app use: the day someone first tapped Fertig, no count, no device. | while the source lists it; `active` turns false when it disappears |
| `opportunity_support_snapshots` | Support counts seen per ingestion run, for momentum | with its opportunity |
| `opportunity_news` | Reports the news ladder judged relevant for a tracked opportunity (Mein Impact) | with its opportunity |
| `council_members` | Current voting members of Dresden council bodies with their Fraktion (OParl sync), for letter recipients | replaced each sync |
| `news_items` | Shelved media pipeline; kept on purpose for later reuse, nothing reads it | until reused or dropped |

### Operations

| Table | Contents | Retention |
|---|---|---|
| `ingestion_schedule` | One row: scheduler on/off and interval (/admin) | — |
| `ingestion_runs` | Every ingestion run; a `running` row is the cross-machine lock | indefinite |
| `api_spend` | AI API cost per day, provider and endpoint | indefinite |
| `usage_counts` | How often an app event happened per Berlin day; event name and count only | indefinite |

### Beta feedback (pseudonymous)

| Table | Contents | Retention |
|---|---|---|
| `card_feedback` | Why a tester threw a card away: reason, optional note, the ranker's score parts, app version, day | 180 days (`feedback_retention_days`, daily cleanup) |
| `beta_feedback` | Free-text messages: kind, text, screen, app version, platform, handled flag, day | 180 days |

### Dropped

`civic_actions`, `pipeline_runs` (202609270010); `feedback` (202611230025);
`user_profiles`, `action_tracking`, `beta_tokens`, `push_subscriptions`,
`action_stats`, `tracking_events`, `mdb_statements` (202611240026).

---

## Dependencies

- Reads: `architecture/dsgvo.md`, `data/ingestion-pipeline.md`
- Referenced by: `features/feed.md`, `features/tracking.md`,
  `technical/api-endpoints.md`
