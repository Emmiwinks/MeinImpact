# General Profile

## Purpose
Defines the demographic and contextual profile fields, how they are
collected, stored, and used to personalise the "what this means for you"
section and letter generation.

---

## Decisions

- **All general profile fields are optional.** Skipping any or all fields
  degrades personalisation but does not block app usage.

- **Profile fields are stored locally in Hive only.** No field is
  transmitted to the backend as part of the user's identity.

- **PLZ is transmitted as a 2-digit prefix only during letter generation.**
  The full PLZ is used locally to look up the MdB via the backend endpoint
  `GET /abgeordnetenwatch/mdb?plz={plz}`. This is a lookup, not storage —
  the backend returns the MdB data and does not store the PLZ.

- **Personal identity fields (name, address) are stored locally only**
  and are used exclusively for placeholder replacement in letters.
  See `architecture/data-flow.md` Flow 4.

- **The demographic profile is collected in onboarding Screen 5** and
  can be edited later in Settings → Profile.

---

## Data Model

Stored in Hive `profile` box alongside the value profile.

```dart
class GeneralProfile {
  // Location
  String? plz;                        // Full 5-digit PLZ, local only

  // Life situation (multi-select)
  List<String> lebenssituation;       // e.g. ['elternteil', 'berufstaetig']

  // Professional sector (single select)
  String? sektor;                     // e.g. 'gesundheit'

  // Housing situation (single select, optional sub-field)
  String? wohnsituation;              // 'mieter' | 'eigentuemer' | null

  // Personal identity for letter pre-filling (optional)
  String? vorname;
  String? nachname;
  String? strasse;                    // Street + number
  String? ort;                        // City name (derived from PLZ lookup)
}
```

---

## Field Definitions

### PLZ
- Format: 5-digit string, validated against German PLZ pattern
- Used for: MdB lookup, PLZ prefix (first 2 digits) in letter generation
- Transmitted: 2-digit prefix only, in letter generation request body
- Never transmitted: full PLZ

### Lebenssituation
Valid keys and display labels:

| Key | Label |
|---|---|
| elternteil | Elternteil |
| eigentuemer | Wohneigentümer/in |
| pflegend | Pflegend tätig |
| rentner | Rentner/in |
| ausbildung | In Ausbildung |
| berufstaetig | Berufstätig |

Multi-select. Empty array is valid.

### Sektor
Valid keys and display labels:

| Key | Label |
|---|---|
| gesundheit | Gesundheit & Pflege |
| handwerk | Handwerk & Industrie |
| bildung | Bildung & Soziales |
| it | IT & Digital |
| landwirtschaft | Landwirtschaft |
| oeffentlich | Öffentlicher Dienst |
| sonstiges | Sonstiges |

Single select. Null is valid.

### Wohnsituation
| Key | Label |
|---|---|
| mieter | Mieter/in |
| eigentuemer | Eigentümer/in |

Single select. Null is valid. Collected in Settings → Profile (not in
onboarding MVP). Relevant for housing-related actions.

### Personal Identity Fields
Collected in Settings → Profile → "Letter details" section.
Not collected during onboarding to reduce friction.

Each field shows the notice: "Stays on your device. Never sent to us."

---

## How Profile Fields Affect the App

### MdB Lookup
When PLZ is set:
```
GET /abgeordnetenwatch/mdb?plz={plz}
Response: {
  name: "Sarah Müller",
  party: "CDU",
  wahlkreis: "Dresden-Nord",
  profile_url: "https://abgeordnetenwatch.de/..."
}
```
Result is cached locally in Hive `profile.mdb` for 30 days.
Backend does not store the PLZ.

### Feed Personalisation
The feed scoring uses general profile fields as a multiplier for action
relevance. This runs locally.

```dart
double demographicBoost(Action action, GeneralProfile profile) {
  // Example: health sector user gets boost on health-topic actions
  if (profile.sektor == 'gesundheit' && action.topics.contains('gesundheit'))
    return 1.3;
  if (profile.lebenssituation.contains('elternteil') &&
      action.topics.contains('bildung'))
    return 1.2;
  // Homeowners get housing boost
  if ((profile.wohnsituation == 'eigentuemer' ||
       profile.lebenssituation.contains('eigentuemer')) &&
      action.topics.contains('wohnen'))
    return 1.2;
  return 1.0; // No boost if no match
}
```

### Letter Generation
The letter generation request includes:
- `plz_prefix`: first 2 digits of PLZ (or omitted if not set)
- `lebenssituation`: list of keys (or empty)
- `sektor`: key (or null)

These are not personal data. They give Mistral enough context to write
relevant letters without exposing the full profile.

Placeholders in generated letter text:
- `{{USER_FULL_NAME}}` → replaced by `${profile.vorname} ${profile.nachname}`
- `{{USER_ADDRESS}}` → replaced by `${profile.strasse}, ${profile.plz} ${profile.ort}`

Replacement happens on-device. Backend never sees real values.

---

## Profile Completeness Display

Settings shows a profile completeness indicator:
- PLZ set: +20%
- Lebenssituation set (≥1): +20%
- Sektor set: +15%
- Value profile ≥4 answered: +30%
- Value profile fully answered: +15%

This is informational only. No feature is gated behind completeness.

---

## Dependencies

- Reads: `architecture/dsgvo.md`, `user/onboarding.md`
- Referenced by: `features/feed.md`, `features/letter-generation.md`,
  `technical/local-storage.md`

---

## Open Questions

- None.
