# GDPR Architecture

## Purpose
Defines how MeinImpact handles user data and stays GDPR compliant. Every
feature that touches user data checks this document first. Rewritten
2026-11-21 against the actual app and backend; the earlier version
described a planned architecture (Hive, push, Sentry, accounts) that was
never built this way.

---

## Principle

**As little as possible leaves the phone.** The app ranks, learns and
remembers on the device. The server only serves public opportunities and
does the few things the device cannot: locating a PLZ, drafting a letter,
and anonymous counts.

---

## Decisions

- **Political data is Art. 9 data.** Values, Lebenslagen, learned topic
  weights, budget priorities, stance choices and the action log can reveal
  political opinions. They stay on the device and are never sent.
- **One exception, by the user's own act: the letter.** What the user types
  under "Was ist dir wichtig?" goes with the opportunity id to the backend
  and on to Mistral to draft the letter. It often contains a political
  opinion, so it is covered by explicit consent (Art. 9(2)(a)). It is not
  stored by us.
- **Stance chips (dafür/dagegen) stay on the device** and only feed the
  user's own ranking. Server-side feedback for improvement is planned and
  needs its own design here first.
- **Anything stored on the server is anonymous:** no account, no
  identifier, no link to a person or device.
- **Personal data never goes into URLs.** PLZ, opportunity ids of tracked
  actions and letter notes travel in request bodies, so access logs never
  show them. Only the 5-digit Kreis key appears in a query string. The
  access log also skips `/v1/opportunities/tracked` and the removed
  `/v1/mdb`, which old app versions still call with the PLZ in the URL.
- **Endpoints the app does not use are removed**, not left running
  (2026-11-21: actions, push, feedback, beta, news, mdb).
- **EU only.** Backend on Fly.io Frankfurt, LLM at Mistral (EU).

---

## What happens to which data

### On the device only (FlutterSecureStorage)

| Data | Store |
|---|---|
| Werte answers (8 values, -2..2) | `user_profile_store` |
| PLZ, Kreis, Wahlkreis, chosen MdB | `user_profile_store` |
| Lebenslagen, Betroffenheit fields | `user_profile_store` |
| Learned topic weights | `user_profile_store` |
| Budget priorities (planned) | `user_profile_store` |
| Stance chips (planned) | device |
| Actions done / starred, streak, badges | `action_log_store`, `starred_actions_store` |
| Notification state | `notification_store` |
| Usage activity markers | `usage` |
| Installation id (random UUID), session tokens | `installation_id_store`, `token_store` |

### Sent, not stored (transient)

| Data | Endpoint | When | Who sees it |
|---|---|---|---|
| Installation id + app version | `POST /v1/auth/anonymous-session` | session start/renewal | backend; carried inside the signed token, no table |
| PLZ | `POST /v1/location` (body) | once when entered | backend; answers Kreis, point, Wahlkreise |
| Kreis key | `GET /v1/opportunities/pool?kreis=` | feed load | backend, access log |
| Opportunity id + letter notes | `POST /v1/letters/stream` (body) | user drafts a letter | backend, Mistral |
| Opportunity id | `POST /v1/opportunities/tracked` (body) | first "Fertig" on a card | backend; only a date is kept (below) |

### Stored on the server, anonymous

| Data | Table | Retention | Purpose |
|---|---|---|---|
| Usage counts per event and Berlin day (name only) | `usage_counts` | indefinite | /admin dashboard |
| Day an opportunity was first marked done (no count, no device) | `opportunities.tracked_since` | while the row exists | decides what Mein Impact follows |

### Stored on the server, pseudonymous (beta feedback)

Only what a tester actively sends. The tester is named by a 12-character
keyed hash of the installation id (HMAC with a key derived from the
server's JWT secret, `services/beta_feedback.py`): the same phone always
gets the same name, so we can tell one tester saying something 30 times
from 15 testers saying it once, but the name leads back to no id and no
person. A reinstall starts a new name. Only the Berlin day is kept, no
time. Never sent to an LLM.

| Data | Table | Retention | Purpose |
|---|---|---|---|
| Card thrown away: opportunity id, reason, optional note (≤500), the ranker's score parts for that card (position, appeal, situation, interest, locality, Haltung; no profile fields), app version | `card_feedback` | 180 days (`feedback_retention_days`, daily cleanup) | recalibrate the ranking |
| Free-text message: kind, text (≤2000), screen, app version, platform | `beta_feedback` | 180 days | fix bugs, collect ideas |

The reason "Möchte ich nicht unterstützen" plus its note can reveal a
political opinion about a concrete matter (Art. 9): covered by explicit
consent, see below.

### Logs

Fly.io keeps platform logs including access lines (client IP, method,
path incl. the Kreis query, status). Request bodies are not logged; no
handler logs request content. Fly's log search currently keeps logs for
7 days (Fly docs, checked 2026-11-21). IP addresses are personal data:
retention and purpose (operation, abuse) belong in the privacy policy.

### Leaving the app

The in-app browser opens registries and petition platforms; their own
privacy policies apply there. Letters are sent from the user's own mail
app; the app only hands over the text and recipients.

---

## Legal basis

| Processing | Basis |
|---|---|
| Letter notes to backend and Mistral | Explicit consent, Art. 9(2)(a) |
| PLZ lookup, Kreis for the feed, anonymous session | Use of the requested service, Art. 6(1)(b) |
| Anonymous usage counts, tracked date | No personal data stored |
| Beta feedback (pseudonymous, may hold political opinions) | Explicit consent, Art. 9(2)(a); sending is voluntary each time |
| Access logs (IP) | Legitimate interest in operation and security, Art. 6(1)(f) |
| Device storage | Strictly necessary for the requested service (§ 25(2) TDDDG) |

---

## Consent (onboarding)

One screen after the intro, before the Werte questions. Blocking; the
"Beispielprofil" path passes through it too.

1. Short plain-language summary on the screen itself (explicit consent
   needs the key facts visible, not only behind a link):
   - Werte, Lebenslage and priorities stay on the phone.
   - For a letter, the user's text goes briefly to an AI in the EU that
     drafts it; we do not store it.
   - Feedback the user sends (why a card went away, messages) is stored
     under a code name for 180 days. On screen: "Wenn du uns Feedback
     gibst, etwa warum du eine Karte weglegst, speichern wir es unter
     einem Codenamen, nicht unter deinem Namen, und löschen es nach 180
     Tagen."
2. Link to the full policy, as a joke: "Und hier das rechtssichere
   Bla-bla zum Gegenlesen."
3. Age confirmation checkbox: at least 16 (GDPR consent age in
   Germany, decided 2026-11-21).
4. Button "Einverstanden".

Recorded on the device only. The full policy is also reachable from the
profile at any time (Google Play expects an in-app link).

Wording is drafted with the onboarding sketches; legal review before the
public launch.

---

## User rights

- **Access / portability:** all personal data is on the device, apart
  from beta feedback. The server cannot find a person's feedback from
  their name or email; only the installation id leads to the code name,
  and it lives on the phone.
- **Erasure:** uninstalling the app deletes everything on the device;
  feedback on the server is deleted after 180 days. An in-app
  "Alle Daten löschen" does not exist yet (open; it could also delete
  the tester's feedback by sending the installation id once).
- **Withdraw consent:** stop drafting letters; uninstall or delete data.

---

## Processors and outbound services

| Service | Purpose | User data | Region |
|---|---|---|---|
| Fly.io | Backend hosting, logs | IP, requests in transit | EU (fra) |
| Supabase | PostgreSQL | anonymous tables only | EU (Frankfurt) |
| Mistral AI | Enrichment (public texts); letter drafts | letter notes; kept 30 days for abuse monitoring unless zero data retention is on | EU |
| Tavily | Impact news search | none (queries from public opportunity titles) | USA (AlphaAI Technologies Inc.) |
| Registries, OParl, Wikidata, Bundestag data | Reading public data | none (outbound only) | — |
| Google Play | Distribution | per Google | — |

DPAs (AVV) with Fly.io, Supabase and Mistral before the public launch.

---

## Privacy by design checklist

For every new feature:

- [ ] Does it send anything from the on-device profile? Then it needs a
      section here and, for political data, explicit consent.
- [ ] Does it put user data in a URL? Move it to the body.
- [ ] Does it store something on the server? It must be anonymous; add it
      to the table above with purpose and retention.
- [ ] Does it call an outside service with user content? Add it to the
      processors table.

---

## Open questions

- Mistral keeps API inputs and outputs for 30 rolling days for abuse
  monitoring unless zero data retention (ZDR) is activated; ZDR is
  requested from Mistral support and covers stateless calls. Request it.
  Until then the consent text says "we do not store it", not "nobody
  stores it", and the policy names the 30 days.
- Tavily sits in the USA. It only gets queries built from public
  opportunity titles, never user data, so it is not a processor of user
  data and needs no mention in the privacy policy. Keep it that way.
- "Alle Daten löschen" in the profile.
- Legacy tables from removed endpoints (`civic_actions`, `action_stats`,
  `tracking_events`, `mdb_statements`, `push_subscriptions`,
  `beta_tokens`) still exist in the database; drop them in a migration.
  `news_items` stays on purpose (shelved media pipeline). (`feedback` was
  dropped in migration 0025.)
- Impressum and legal entity: unchanged from the earlier plan (sole
  trader/GbR now, gGmbH before public launch); confirm.

## Dependencies

- Referenced by: `user/values-and-priorities.md`, `user/onboarding.md`,
  `features/letter-generation.md`, `technical/api-endpoints.md`
