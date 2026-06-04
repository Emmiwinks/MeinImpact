# Action Types

## Purpose
Defines the three action types available in MVP, their UI flow, external
targets, and specific behaviour per type.

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
