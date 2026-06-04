# GDPR Architecture

## Purpose
Defines how MeinImpact achieves and maintains GDPR compliance. All features
that handle any form of user data must reference this document before
implementation.

---

## Decisions

- **Political profile data is GDPR Art. 9 special category data.** Value
  scores, topic selections, whitelist, blacklist, and any derived political
  inference are subject to the highest protection level. They are never
  transmitted to the backend under any circumstances in MVP.

- **The backend never processes Art. 9 data.** If a future feature requires
  the backend to receive profile data, it must implement E2E encryption (V2
  architecture) so the backend stores only an opaque blob it cannot read.
  This requires a written architecture decision record before implementation.

- **Data minimisation is enforced at design time.** Every API endpoint and
  database table is designed with the minimum viable data set. No field is
  added without a documented purpose and retention rule.

- **All server-side data is anonymous or pseudonymous.** No data point stored
  on the backend can be linked to a real person without the device it
  originated from. Beta tokens and push tokens are random UUIDs with no
  identity attached.

- **Fly.io EU region is mandatory.** All backend infrastructure runs in the
  EU. Data never transits to non-EU regions. This applies to the database
  (Neon EU), the backend (Fly.io Frankfurt), and any managed services used.

- **Third-party AI providers receive no personal data.** Mistral API calls
  contain only action text and anonymous context. Personal identity values
  are replaced with placeholders before any text leaves the device.

- **Users have full control over local data.** The app provides a visible
  option to delete all local data (profile, gamification, settings, cache)
  at any time without requiring an account or internet connection.

- **AI-generated content is disclosed without undermining trust.** Letters
  are framed as "pre-drafted based on your profile" rather than labelled
  "AI-generated". Legal compliance with the EU AI Act is met via AGB
  disclosure and a one-time onboarding acknowledgement.

---

## Data Classification

### Category A: Art. 9 Special Category (Device only, never transmitted)

Political beliefs and any data that could reconstruct them.

| Data | Storage | Retention |
|---|---|---|
| Value scores (8 integers) | Hive `profile` | Until user deletes locally |
| Topic selections | Hive `profile` | Until user deletes locally |
| Whitelist / blacklist | Hive `profile` | Until user deletes locally |
| Completed action history | Hive `gamification` | Until user deletes locally |

### Category B: Anonymous Operational Data (Backend, no identity link)

| Data | Storage | Retention | Purpose |
|---|---|---|---|
| Beta token (UUID) | PostgreSQL `beta_tokens` | Duration of beta | Access control |
| Push token (device-issued) | PostgreSQL `push_subscriptions` | Until unsubscribed | Notifications |
| Action completion count | PostgreSQL `action_stats` | Indefinite | Impact display |
| Feedback rating + comment | PostgreSQL `feedback` | 12 months | Quality assurance |
| API spend per day | PostgreSQL `api_spend` | 24 months | Cost monitoring |
| Tracking events | PostgreSQL `tracking_events` | Indefinite | Civic impact data |

### Category C: Personal Identity (Device only, never transmitted)

| Data | Storage | Retention |
|---|---|---|
| Full name | Hive `profile` (optional) | Until user deletes |
| Address | Hive `profile` (optional) | Until user deletes |
| City | Hive `profile` (optional) | Until user deletes |

Category C values are inserted as placeholders `{{USER_FULL_NAME}}`,
`{{USER_ADDRESS}}`, `{{USER_CITY}}` when generating letters. Replacement
with real values happens on-device immediately before the user sends.
The backend and Mistral never see the real values.

### Category D: Demographic Context (Transient, device-originated, not stored)

Life situation fields that are sent to the backend in context and letter
generation requests. They are NOT Art. 9 data (no political belief content).
They are processed transiently: passed to Mistral for generation and
immediately discarded. Never written to the database. Never written to logs.

| Data | Storage on Device | Transmitted to Backend | Stored on Backend |
|---|---|---|---|
| PLZ (full) | Hive `profile` | MdB lookup only | ❌ Not stored |
| PLZ prefix (2 digits) | Derived locally | Context + letter flows | ❌ Not stored |
| Lebenssituation | Hive `profile` | Context + letter flows | ❌ Not stored |
| Beruflicher Sektor | Hive `profile` | Context + letter flows | ❌ Not stored |
| Wohnsituation | Hive `profile` | Context + letter flows | ❌ Not stored |

Backend log configuration must exclude request bodies for the
`/actions/{id}/context` and `/letters/stream` endpoints. This must be
verified before production launch. See `technical/monitoring.md`.

---

## Legal Basis for Processing

| Data | Legal Basis | GDPR Article |
|---|---|---|
| Category A (profile) | Explicit consent at onboarding | Art. 9(2)(a) |
| Category B (operational) | Legitimate interest (service operation) | Art. 6(1)(f) |
| Category C (identity) | Explicit consent at point of use | Art. 6(1)(a) |
| Category D (demographic, transient) | Explicit consent at onboarding | Art. 6(1)(a) |
| Push token | Explicit opt-in within app | Art. 6(1)(a) |

---

## Consent Architecture

### Onboarding consent (mandatory, blocking)
Before the profile wizard begins, the user must confirm:

1. Age confirmation: "I confirm I am at least 18 years old."
2. Profile consent: "My political profile stays on my device. I consent to
   MeinImpact storing an anonymous access token on a server in the EU.
   If I provide life situation details (profession, family situation),
   these are sent to the AI for personalisation and immediately discarded."
3. AI disclosure: "Action recommendations and letter drafts are pre-drafted
   by AI based on my profile. I review and send them myself."

All three must be confirmed. The app does not proceed until all are accepted.
Consent is recorded locally in `meta.consents_confirmed = true`.

### Push notification consent (optional, separate)
Requested only after the user completes their first action. A separate
system permission dialog follows app-level confirmation. Stored locally
in `settings.notifications_enabled`.

### Identity placeholder consent (optional, at point of use)
When the user first adds their name or address for letter pre-filling,
a one-sentence notice: "This stays on your device and is never sent to us."

---

## User Rights Implementation

### Right to access (Art. 15)
- **Local data**: Settings → Profile → "Show my data" exports all Hive
  boxes as a human-readable JSON file. No network request required.
- **Server data**: The backend holds no data linked to the user. The
  privacy policy states this explicitly. No server-side export endpoint
  is required.

### Right to erasure (Art. 17)
- **Local data**: Settings → "Delete all my data" wipes all Hive boxes
  and unregisters the push token. Confirmed with a single tap.
- **Server data**: Unregistering push token deletes the push_subscription
  row. Beta token row is not deleted (it is anonymous; deletion would
  allow reuse of the invite slot — acceptable trade-off documented here).

### Right to data portability (Art. 20)
- Covered by the same JSON export as Right to Access. File is
  machine-readable and can be imported into a new device.

### Right to withdraw consent (Art. 7(3))
- Profile consent: deleting local data constitutes withdrawal.
- Push consent: Settings → Notifications → Off unregisters the token
  and deletes the push_subscription row immediately.

---

## Third-Party Data Processors

All processors are GDPR-compliant and operate under a Data Processing
Agreement (DPA).

| Processor | Purpose | Data shared | Region |
|---|---|---|---|
| Fly.io | Backend hosting | Anonymous operational data | EU (Frankfurt) |
| Neon | PostgreSQL hosting | Anonymous operational data | EU |
| Mistral AI | Letter + classification | Action text, no personal data | EU |
| Tavily | Web search | Action title/query, no personal data | EU |
| NewsData.io | News feed | No user data (outbound query only) | EU |
| FCM (Google) | Push notifications | Anonymous push token | EU servers configurable |
| APNS (Apple) | Push notifications | Anonymous push token | Apple EU servers |
| Sentry | Error tracking | Stack traces, no user data | EU |

DPAs must be signed with each processor before production launch.

---

## AI Act Compliance (EU AI Act, effective August 2026)

MeinImpact uses AI for:
1. **Action classification** (backend, not user-facing) — no disclosure required
2. **"What this means for you" context** (user-facing) — disclosed in onboarding
3. **Letter pre-drafting** (user-facing) — disclosed in onboarding + framed as
   "pre-drafted based on your profile" in UI

The onboarding consent (point 3 above) covers both user-facing AI uses.
No per-generation label is required after onboarding consent is given,
provided the framing "pre-drafted" is consistently used in the UI.

MeinImpact does not use AI for consequential decisions about individuals
(no credit scoring, no profiling for third parties) and therefore falls
outside the high-risk AI system category.

---

## Privacy by Design Checklist

Applied to every new feature before implementation:

- [ ] Does this feature transmit any Category A data? If yes: blocked until
      E2E encryption (V2) is implemented.
- [ ] Does this feature add a new data point to the backend? If yes: document
      purpose, legal basis, and retention rule here before writing code.
- [ ] Does this feature call a third-party API with user context? If yes:
      verify no personal data is included; use placeholders if needed.
- [ ] Does this feature show user-facing AI output? If yes: use "pre-drafted"
      framing, not "AI-generated".
- [ ] Does this feature require a new consent? If yes: add it to the onboarding
      consent flow or obtain it at point of use.

---

## Impressum and Legal Entity

- Current: Sole trader / GbR — virtual office address (e.g. Clevver),
  not private home address.
- Target before first public launch: gGmbH with registered office address.
- Datenschutzbeauftragter: not required below 20 employees processing
  personal data regularly. Reassess at scale.

---

## Data Breach Response

In the event of a backend data breach:
- Exposed data is anonymous (beta tokens, push tokens, action counters).
- No personal data or political profiles are exposed because none are stored.
- Notification to supervisory authority (BfDI) within 72 hours if the breach
  poses a risk to rights and freedoms — low likelihood given data anonymity.
- User notification: not required unless risk to individuals is established.

---

## Dependencies

- Reads: `architecture/overview.md`
- Referenced by: `user/authentication.md`, `user/value-profile.md`,
  `user/general-profile.md`, `features/letter-generation.md`,
  `technical/api-endpoints.md`

---

## Open Questions

- [ ] DPA with FCM/Google: confirm EU server routing is enforceable
      before push notifications go to production.
- [ ] Sentry configuration: verify no device identifiers are captured
      in error payloads before production launch.
