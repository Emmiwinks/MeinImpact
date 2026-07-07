# Data Flow

## Purpose
Describes every data movement in the system: what travels between device,
backend, and third-party services, and what never leaves each boundary.

---

## Decisions

- **The device is the trust boundary for political data.** Nothing in Category A
  (see `architecture/dsgvo.md`) crosses the device boundary in any direction.

- **The backend is a dumb pool server for the MVP.** It serves the action pool,
  validates beta tokens, stores anonymous counters, and proxies AI calls.
  It makes no personalisation decisions.

- **All personalisation is a local computation.** Scoring, filtering, and
  ranking happen entirely in Flutter after the pool is downloaded.

- **AI calls are proxied through the backend.** The app never calls Mistral
  directly. The backend strips any user context before forwarding and never
  logs request bodies containing action text.

---

## Flow 1: App Startup

```
Flutter app
  │
  ├─ 1. Read meta.beta_token from Hive
  ├─ 2. GET /health?token={beta_token}
  │       Backend: validate token exists in beta_tokens table
  │       Response: { valid: true, pool_version: "2026-06-04" }
  ├─ 3. Compare pool_version with locally cached version
  └─ 4. If outdated → Flow 2 (Pool Download)
        If current  → render feed from local cache
```

No profile data is involved. No identity is transmitted.

---

## Flow 2: Action Pool Download

```
Flutter app
  │
  └─ GET /actions/pool?token={beta_token}
          Backend: SELECT active actions from PostgreSQL
          Response: JSON array, ≤ 100 items, ≤ 150 KB
          [
            {
              id, title, action_type, summary, urgency, deadline,
              source_url, effort_minutes, impact_hint,
              pro_argumente[], contra_argumente[],
              werte_relevanz{}, action_types[],
              is_controversial, position_required,
              momentum_score, created_at
            }
          ]

Flutter app (local, no network)
  ├─ Read profile from Hive (werte axes only — no topics)
  ├─ Score each action: werte_match × 0.60 + urgency × 0.25
  │                    + deadline_bonus × 0.10 + momentum × 0.05
  ├─ Filter: score ≥ 0.2 threshold
  ├─ Sort descending
  └─ Render feed (no hardcoded limit)
```

The backend returns the same pool to every device. Personalisation is
entirely client-side. The backend never sees the profile.

---

## Flow 3: Action Detail + "What This Means for You"

```
Flutter app
  ├─ Read demographic fields from Hive profile (non-Art.9 fields only)
  └─ POST /actions/{action_id}/context?token={beta_token}
          Body: {
            lebenssituation: ["elternteil", "berufstaetig"],  // or []
            sektor: "gesundheit",                              // or null
            plz_prefix: "01",                                  // first 2 digits only, or null
            wohnsituation: "mieter"                            // or null
          }
          Backend:
            1. Fetch action from PostgreSQL
            2. Fetch cached Tavily context (if available)
            3. Call Mistral: prompt contains action text + Tavily context
               + demographic fields for personalisation
               NO value scores, NO full PLZ, NO personal identity
            4. Return generated context text (not streamed)
            NOTE: demographic fields are used transiently for generation
                  and are never stored or logged
          Response: { context: "..." }

Flutter app
  └─ Display context beneath action detail
```

The demographic fields (lebenssituation, sektor, plz_prefix, wohnsituation)
are not Art. 9 special category data. They describe life situation, not
political beliefs. Sending them enables genuine personalisation such as:
"As a healthcare worker in Saxony, this decision directly affects your
shift pay schedule."

Value scores and tone descriptors are NOT sent in this flow. They are
used only in the letter generation flow (Flow 4).

---

## Flow 4: Letter Draft Generation (Streaming)

```
Flutter app
  ├─ Build prompt context locally:
  │    - Action title + why_now from pool cache
  │    - Recipient name + party from Abgeordnetenwatch (fetched at Flow 3)
  │    - Placeholders: {{USER_FULL_NAME}}, {{USER_ADDRESS}}, {{USER_CITY}}
  │    - Tone derived from local value profile (mapped to adjectives,
  │      e.g. "pragmatic", "community-oriented") — no raw scores sent
  │
  └─ POST /letters/stream?token={beta_token}
          Body: { action_id, recipient, tone_descriptors[], plz_region }
          Backend:
            1. Validate token
            2. Check rate limit (Redis): letters per device per day
            3. Check global budget (Redis): daily spend ceiling
            4. Stream Mistral response via SSE
          Response: text/event-stream
            data: "Sehr geehrte"
            data: " Frau"
            data: " Müller,"
            ...
            data: [DONE]

Flutter app
  ├─ Render tokens as they arrive (typewriter effect)
  ├─ On [DONE]: replace {{USER_FULL_NAME}} etc. with Hive values
  └─ Present editable draft to user
```

The backend receives tone descriptors (strings like "community-oriented"),
a PLZ region prefix (first 2 digits only), and placeholder text.
It never receives raw value scores or full PLZ.

---

## Flow 5: Action Submission

```
Flutter app
  ├─ User taps "Send" on external channel (Abgeordnetenwatch, petition, etc.)
  ├─ App opens external URL or email client — letter is sent outside MeinImpact
  └─ POST /actions/{action_id}/complete?token={beta_token}
          Body: { action_type }
          Backend:
            UPDATE action_stats SET completion_count = completion_count + 1
            WHERE action_id = {action_id}
          Response: { ok: true }

Flutter app
  ├─ Write action_id to Hive gamification.completed_action_ids[]
  ├─ Increment local streak
  └─ Navigate to confirmation screen
```

No letter content is sent to the backend. Completion is a single counter
increment with no user linkage.

---

## Flow 6: Push Notification Registration

```
Flutter app (after user opts in)
  ├─ Request FCM/APNS push token from platform
  └─ POST /push/register?token={beta_token}
          Body: { push_token }
          Backend:
            INSERT INTO push_subscriptions (push_token, action_ids=[])
          Response: { ok: true }
```

No profile data. No identity. The push_token is a device identifier
issued by Google/Apple, not by MeinImpact.

---

## Flow 7: Push Notification Subscription to Action

```
Flutter app
  └─ POST /push/subscribe?token={beta_token}
          Body: { push_token, action_id }
          Backend:
            UPDATE push_subscriptions
            SET action_ids = array_append(action_ids, action_id)
            WHERE push_token = {push_token}
```

---

## Flow 8: Tracking Event → Push Notification

```
Backend cronjob (or webhook from external source)
  ├─ Detects tracking event (e.g. Bundestag vote result)
  ├─ INSERT INTO tracking_events (action_id, event_type, description, ...)
  ├─ SELECT push_token FROM push_subscriptions WHERE action_id = ANY(action_ids)
  └─ Send push notification via FCM/APNS
          Payload: { title: "Ergebnis verfügbar", action_id }
          NO profile data, NO political content in payload

Flutter app (on notification tap)
  └─ Navigate to tracking detail screen for action_id
```

---

## Flow 9: Feedback Submission

```
Flutter app
  └─ POST /feedback?token={beta_token}
          Body: { action_id, rating: 1–5, comment: "..." }
          Backend:
            INSERT INTO feedback (action_id, rating, comment)
            — no user_id, no device_id
          Response: { ok: true }
```

---

## Flow 10: Daily Ingestion Cronjob (Backend only)

```
Backend (APScheduler, runs at 03:00 CET)
  │
  ├─ Stage 0: DIP API → Vorgänge filtered by active beratungsstand
  │    (2./3. Beratung, Ausschussberatung) + recent aktualisiert date
  │    Each item scored by imminence (stage × recency)
  │
  ├─ Stage 1: Tavily → broad petition search on WeAct + openPetition
  │
  ├─ Deduplicate (URL exact + fuzzy title match)
  │
  ├─ Prefilter (title length, German language, petition rules)
  │
  ├─ Stage 4: Tavily enrichment — SKIPPED in MVP
  │
  ├─ Stage 5: Mistral classify_action:
  │    returns urgency, werte_relevanz{}, pro/contra_argumente[],
  │    action_types[], is_controversial, position_required
  │    (no topics — classification is topic-free)
  │
  ├─ INSERT INTO civic_actions (...) ON CONFLICT (source_url) DO UPDATE
  │
  ├─ Deactivate actions past deadline + 7 days grace
  └─ Log run to pipeline_runs
```

No user data involved at any point.

---

## Data Boundary Summary

| Data | Device | Backend | Mistral | Tavily | NewsData |
|---|---|---|---|---|---|
| Value scores | ✅ | ❌ | ❌ | ❌ | ❌ |
| Werte axes | ✅ | ❌ | ❌ | ❌ | ❌ |
| PLZ (full) | ✅ | MdB lookup only, not stored | ❌ | ❌ | ❌ |
| PLZ prefix (2 digits) | ✅ | Context + letter flows, not stored | ✅ transient | ❌ | ❌ |
| Lebenssituation | ✅ | Context + letter flows, not stored | ✅ transient | ❌ | ❌ |
| Sektor | ✅ | Context + letter flows, not stored | ✅ transient | ❌ | ❌ |
| Wohnsituation | ✅ | Context + letter flows, not stored | ✅ transient | ❌ | ❌ |
| Full name / address | ✅ | ❌ (placeholders only) | ❌ | ❌ | ❌ |
| Action pool | Cache | ✅ | ❌ | ❌ | ❌ |
| Beta token | ✅ | ✅ | ❌ | ❌ | ❌ |
| Push token | ✅ | ✅ | ❌ | ❌ | ❌ |
| Streak / badges | ✅ | ❌ | ❌ | ❌ | ❌ |
| Action completion | ✅ | Counter only | ❌ | ❌ | ❌ |
| Letter content | ✅ | Streamed, not stored | Placeholders | ❌ | ❌ |
| Tone descriptors | ✅ | Letter flow only, not stored | ✅ transient | ❌ | ❌ |

**Transient** = passed through to Mistral in the request, never written
to database, never written to logs. Verified by backend log configuration.

---

## Dependencies

- Reads: `architecture/overview.md`, `architecture/dsgvo.md`
- Referenced by: all `data/`, `features/`, and `technical/` specs

---

## Open Questions

- None.
