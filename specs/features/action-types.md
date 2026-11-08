# Action Types

## Purpose
Defines the three action types available in MVP, their UI flow, external
targets, and specific behaviour per type.

---

## Status (2026-11-08): supersedes the flows below where they conflict

Actions are now registry opportunities (`ingestion-pipeline.md`), not the
three DIP-era types. The app's `OpportunityKind` mirrors the backend's
`ActionKind`: petition, consultation, public_display, survey, event,
decision (upcoming council vote), notice, other.

Decided with the user for the MVP:

- **Taking action stays inside the app.** Listed actions (petitions,
  consultations, surveys, Bürgerbefragungen) open in an in-app browser. A
  "Fertig" button bottom right marks the action done; no separate "Hast du
  mitgemacht?" question. Completion stays self-reported.
- **Native only for the in-app browser.** Every action site blocks framing
  (X-Frame-Options / CSP frame-ancestors, checked 2026-11-06: openPetition,
  WeAct, abgeordnetenwatch, Beteiligungsportal Sachsen, Bundestag
  ePetitionen, FragDenStaat, EU Have your say). Android/iOS use a WebView.
- **The web build is a teaser (decided 2026-11-09).** Feed, details and
  profile work; every action button reads "In der App mitmachen" and
  opens a sheet pointing to the app (`MEINIMPACT_APP_DOWNLOAD_URL`, today
  the landing page's beta section). No web-specific workarounds: the full
  experience, and the feedback that matters, is the native app. iPhone
  testers therefore need an iOS build (TestFlight).
- **In-app browser design (decided 2026-11-08):**
  - `webview_flutter` (Android WebView, iOS WKWebView). JavaScript on,
    cookies kept in the app's own store. Non-http links (`mailto:`,
    `tel:`, `intent:`) go to the system. "Im Browser öffnen" in the menu
    is the fallback for anything the WebView cannot do (Google sign-in,
    some captchas, uploads); no per-site workarounds.
  - Full-screen route: close, domain, progress bar, menu (Im Browser
    öffnen, Neu laden, Link kopieren). Android back goes through WebView
    history first. "Fertig" sits right-aligned in a fixed bottom bar, not
    a floating button, so it never covers the site's own submit button.
  - Closing without "Fertig" stores nothing and asks nothing. "Fertig"
    goes straight back to the feed with a short "Stark, erledigt!"
    message; no confirmation sheet and no undo (decided 2026-11-08: an
    accidental tap is rarer than the extra tap is annoying).
  - "Fertig" shows for every kind with a source link except decisions
    (letter flow). For events it means "signed up".
  - A done action leaves the feed; it reappears in Mein Impact (later).
  - The `acted` interest signal fires on "Fertig", not on opening the
    action; opening it counts as `opened`.
- **Action log on the device:** `ActionLogStore`, its own
  `flutter_secure_storage` key `action_log_v1` (political participation
  is GDPR Art. 9 data, so encrypted like the profile, and separate from
  it so editing the profile never wipes history). One entry per
  opportunity id with `doneAt`, `via` (`in_app_browser`,
  `letter`) and a snapshot (title, kind, source, link, deadline, tags) so
  Mein Impact can show actions that have left the pool. Ids are stable:
  rows are upserted on (source_id, external_id). Lost on Android
  uninstall; no server copy by design.
- **No server-side record of done actions (user decided 2026-11-08),** not
  even an anonymous counter. Whether Mein Impact needs aggregate counts is
  to be discussed later; if it comes back, the conditions were: count
  only (no token or time per event), shown from ~5 upward, delayed
  increments, privacy-policy note on transient IP processing.
- **Letter pop-up for decisions (built 2026-11-08):** CTA "Brief
  schreiben" opens a full-screen letter view: an optional "Was ist dir
  wichtig?" field (max 1000 chars, sent as `notes`; nothing from the
  profile is sent), "Brief erstellen" streams the draft from
  `POST /v1/letters/stream` (`opportunity_id`, `notes`) into an editable
  field, then "Kopieren" / "Mail-App" (mailto with subject, body; no
  recipients yet) and "Fertig" (logged with `via: letter`). With notes the
  letter argues the user's stance; without notes it stays neutral. It
  never invents facts about the person nor states their gender (an
  optional gender setting was discussed and left out for now).
- **Letter recipients (built 2026-11-09, replaces the per-person plan
  below):** OParl rarely carries personal emails (1 of 10 current
  Stadträte sampled), so a letter goes to the **Fraktion offices** of the
  members of the responsible body, one address per Fraktion, all
  pre-selected, alphabetical, untickable; never personal addresses, even
  where known (equal treatment). The responsible body: the body meeting on
  the paper; for a Stadtrat item the committees in the paper's
  consultation chain, else the Stadtrat itself (`recipient_bodies`, set by
  the OParl source). Members come from a weekly OParl people walk
  (`council_members`, ~10 min, run inside ingestion when older than 7
  days); office addresses from a hand-made table
  (`infrastructure/council/offices.py`; a Fraktion without an address
  shows as "Adresse fehlt noch" and is reported on /admin).
  Stadtbezirksbeirat/Ortschaftsrat items: member names only, no addresses
  yet. `GET /v1/opportunities/{id}/recipients`. The Wahlkreis option
  below is not built.
- **Decisions get an AI-drafted letter in a pop-up** (to the members of
  the deciding body), sent from the same in-app flow, then "Fertig". The
  letter generator still runs on the old `/v1/actions` stack and has to be
  moved onto opportunities; recipients come from OParl memberships.
- **Letter recipients for council decisions (decided 2026-11-08):**
  - *Default:* the members of the committee responsible for the topic,
    pre-selected. For a Stadtrat item that is the committee in the paper's
    consultation chain (the advising committee); if the deciding body is
    itself a committee, its members. From OParl memberships; emails from
    OParl persons, Fraktion office as fallback.
  - *Additional option:* the Stadtrat members elected in the user's
    Wahlkreis. Needs a hand-made table per election period (Kommunalwahl
    2024: who was elected where, which Stadtteile form each Wahlkreis),
    matched via the user's Stadtteil from the profile.
  - *Stadtbezirksbeirat / Ortschaftsrat items:* the members of that body.
  - *Not:* all 70 Stadtrat members (reads as mass mail).
  - *Neutral:* never chosen by party or by the user's profile; everyone
    listed with party in a neutral order; the letter text does not depend
    on the recipients. The user can deselect or add.
  - *Sending:* one email from the user's own mail app with all selected
    recipients openly in "An", then "Fertig".
- **MeinImpact still never sends or signs on the user's behalf.**
- **Roadmap, not MVP:** an optional gender/pronouns setting in the
  profile, used only for letters (on device, sent only with a letter
  request; unset keeps today's gender-neutral wording);
  auto-filling forms on action sites (per-site fill
  rules, needs name/email stored on device: a deliberate decision);
  actions that need leaving the house (demos, Einwohnerfragestunde);
  Landtag Sachsen decisions; Bundestag decisions (low expected impact).
- **Release target:** testers install the Android app from Google Play's
  internal testing track by 2026-11-12. Public listing later (a new
  personal developer account needs a 12-tester, 14-day closed test first).

---

## Decisions

- **Three action types in MVP:** Brief (letter to MdB), Petition
  (Bundestag or WeAct), Anfrage (public question via Abgeordnetenwatch).

- **MeinImpact never sends anything on behalf of the user.** Every action
  is completed by the user in an external channel. MeinImpact generates
  the content and opens the external channel.

- **Letter uniqueness is enforced.** Each generated letter draft is
  linguistically unique. The user is encouraged to personalise further.

- **Completion is self-reported.** After opening the external channel,
  the app asks "Hast du die Aktion abgeschlossen?" The user confirms.
  No technical verification is possible or attempted.

---

## Action Type 1: Brief (Letter to MdB)

### When available
Action has `action_types` containing `'brief'` AND the user has PLZ set
(so their MdB can be identified) AND `position_required=false` OR user
has a clear value profile position on the relevant axes.

### Flow

```
1. Action detail screen
   → "Brief schreiben" button

2. Letter generation screen
   → Streaming letter draft appears (typewriter effect)
   → Draft contains {{USER_FULL_NAME}}, {{USER_ADDRESS}} placeholders
   → "Anpassen" button opens editable text field

3. Edit screen (optional)
   → User can freely edit the letter
   → Placeholder labels visible as inline hints
   → "Fertig" returns to preview

4. Send screen
   → "Brief senden via Abgeordnetenwatch" (primary)
   → "Per E-Mail senden" (secondary, if MdB email available)
   → "Brief kopieren" (tertiary, clipboard)

5. External channel opens
   → Abgeordnetenwatch profile pre-opened (deep link or browser)
   → OR mail client opens with letter pre-filled in body

6. Return to app confirmation
   → "Hast du den Brief abgeschickt?"
   → Ja → action marked complete, streak updated, confirm screen
   → Nein → return to send screen

7. Confirm screen
   → Streak badge
   → "Wir benachrichtigen dich wenn [MdB] zum Thema abstimmt"
   → Option to subscribe to MdB statement tracking
```

### Letter generation request
```dart
// Sent to POST /letters/stream
{
  'action_id': action.id,
  'recipient_name': mdb.name,
  'recipient_party': mdb.party,
  'recipient_wahlkreis': mdb.wahlkreis,
  'tone_descriptors': profile.deriveToneDescriptors(),
  'lebenssituation': profile.lebenssituation,
  'sektor': profile.sektor,
  'plz_prefix': profile.plz?.substring(0, 2),
  'wohnsituation': profile.wohnsituation,
}
```

### Abgeordnetenwatch deep link
```
https://www.abgeordnetenwatch.de/profile/{mdb_slug}/contact
```
If contact URL not available: fallback to profile page.

### No MdB available
If PLZ is not set: show prompt to enter PLZ before letter generation.
If MdB lookup fails: show "Wir konnten deinen Abgeordneten nicht ermitteln.
Bitte überprüfe deine PLZ in den Einstellungen."

---

## Action Type 2: Petition

### Sub-types
- `bundestag_petition`: Bundestag online petition portal
- `weact_petition`: WeAct / Campact petition

### When available
Action has `action_types` containing `'petition'` and action is still
active (past deadline check done at pool download).

### Flow

```
1. Action detail screen
   → "Petition unterzeichnen" button

2. Petition info screen
   → Signature count (if available)
   → Progress bar toward quorum (if known)
   → "Zur Petition" button

3. External browser opens
   → Direct link to petition page
   → No pre-filling (petition platforms handle their own forms)

4. Return to app confirmation
   → "Hast du die Petition unterzeichnet?"
   → Ja → complete, streak, confirm
   → Nein → return

5. Confirm screen
   → "Wir benachrichtigen dich wenn die Petition das Ziel erreicht"
   → Tracking subscription offered
```

### No letter generation for petitions
Petitions do not use the letter generation flow. The external platform
handles the signing process.

### Quorum display
```dart
Widget quorumProgressBar(Action action) {
  if (action.signatureCount == null || action.quorumTarget == null)
    return SizedBox.shrink();

  final progress = action.signatureCount! / action.quorumTarget!;
  return Column(children: [
    LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
    Text('${action.signatureCount} von ${action.quorumTarget} Unterschriften'),
  ]);
}
```

---

## Action Type 3: Anfrage (Abgeordnetenwatch Question)

### When available
Action has `action_types` containing `'anfrage'` AND user has PLZ set.

### Description
The user submits a public question to their MdB via Abgeordnetenwatch.
Questions are publicly visible on the platform. MdBs are notified and
encouraged to respond publicly.

### When to use vs Brief
- Anfrage: when the user wants a public, documented answer from their MdB
- Brief: when the user wants to express a position or request action

The AI classifier sets `action_types` to include both where appropriate,
and the app shows both options on the action detail screen.

### Flow

```
1. Action detail screen
   → "Öffentliche Anfrage stellen" button

2. Question generation screen
   → Streaming question draft (shorter than letter, 2–4 sentences)
   → Question is pre-filled to be specific and answerable
   → "Anpassen" available

3. External channel
   → Opens Abgeordnetenwatch question form for MdB
   → URL: https://www.abgeordnetenwatch.de/profile/{mdb_slug}/ask
   → Question text available to copy-paste

4. Confirmation flow
   → Same as Brief: self-reported completion

5. Confirm screen
   → "Wenn [MdB] antwortet, siehst du es auf Abgeordnetenwatch"
   → Link to MdB profile saved locally for easy follow-up
```

### Question generation request
```dart
// Sent to POST /letters/stream with type='anfrage'
{
  'action_id': action.id,
  'type': 'anfrage',
  'recipient_name': mdb.name,
  'recipient_party': mdb.party,
  'tone_descriptors': profile.deriveToneDescriptors(),
  'lebenssituation': profile.lebenssituation,
  'plz_prefix': profile.plz?.substring(0, 2),
}
```

---

## Shared Behaviour Across All Types

### Time estimate display
Shown on feed card and action detail:
- Brief: ~3 Min (generation + edit + send)
- Petition: ~1 Min (click through + sign)
- Anfrage: ~2 Min (generation + submit)

### "Anpassen" (edit) always available
All generated text can be edited before sending. The edit button is
always visible. Users are encouraged with the label:
*"Mach ihn zu deinem — auch ein Satz reicht."*

### AI disclosure
Below every generated text block:
*"Auf Basis deines Profils vorformuliert."*
In small grey text. Not a warning, just context.

### Completion tracking
On confirmed completion:
```dart
// Local
Hive.box('gamification')
  .get('completed_this_week', defaultValue: [])
  ..add(action.id);

// Server (anonymous counter only)
await api.post('/actions/${action.id}/complete',
  body: {'action_type': actionType});
```

### If no PLZ set (for Brief and Anfrage)
Show inline prompt on action detail:
*"Für diesen Brief brauchen wir deine Postleitzahl."*
Tapping opens a minimal PLZ entry bottom sheet (not full settings).
PLZ is saved to Hive profile on entry.

---

## Accessibility

- All action buttons have Semantics labels
- External link opening is announced to screenreader
- Confirmation dialogs are accessible via keyboard/switch
- Edit text fields meet minimum contrast requirements

---

## Localisation

All strings in `l10n/`. Action type names, flow labels, and confirmations
are fully localised. German is default.

---

## Dependencies

- Reads: `features/feed.md`, `features/letter-generation.md`,
  `user/general-profile.md`, `data/sources-federal.md`
- Referenced by: `features/tracking.md`, `features/gamification.md`,
  `technical/api-endpoints.md`

---

## Open Questions

- [ ] Abgeordnetenwatch question form: confirm that the /ask deep link
      accepts pre-filled query parameters, or document that copy-paste
      is the only available method.
