# Value Profile

## Purpose
Defines the political value model, how scores are stored, and how they are
used for feed scoring and letter tone derivation.

---

## Decisions

- **The 8values model is the basis.** Four axes, two questions per axis,
  scores from -2 to +2. MIT licence. See https://8values.github.io.

- **Raw scores never leave the device.** The backend and AI providers never
  receive numeric value scores. Letter generation receives tone descriptors
  (human-readable strings) derived from scores, not the scores themselves.

- **The profile is static after onboarding.** There is no in-app mechanism
  to update the value profile in MVP. A full settings screen for profile
  editing is a V2 feature.

- **Neutral (0) scores are valid.** Up to 4 of 8 questions may remain at 0.
  Neutral scores contribute no weight in axis calculations.

- **Axis scores are derived from question pair averages.** Each axis has
  two questions. The axis score is the mean of the two question scores.

---

## Data Model

Stored in Hive `profile` box.

```dart
class ValueProfile {
  // Raw question scores (-2 to +2, 0 = neutral/unanswered)
  int wirtschaft_gleichheit;   // Q1
  int wirtschaft_staat;        // Q2
  int diplomatie_nation;       // Q3
  int diplomatie_welt;         // Q4
  int freiheit_staat;          // Q5
  int freiheit_sicherheit;     // Q6
  int wandel_tradition;        // Q7
  int wandel_zukunft;          // Q8
}
```

---

## Axis Derivation

Four axes derived from question pairs:

```dart
double get axisWirtschaft =>
    (wirtschaft_gleichheit + wirtschaft_staat) / 2.0;
// Negative = equality/state, Positive = market/individual

double get axisDiplomatie =>
    (diplomatie_nation + diplomatie_welt) / 2.0;
// Negative = national, Positive = global/cooperative

double get axisFreiheit =>
    (freiheit_staat + freiheit_sicherheit) / 2.0;
// Negative = liberty/rights, Positive = authority/security

double get axisWandel =>
    (wandel_tradition + wandel_zukunft) / 2.0;
// Negative = tradition/stability, Positive = progress/change
```

Axis range: -2.0 to +2.0. A value of 0.0 means neutral or unanswered.

---

## Feed Scoring: Werte Match

Each action in the pool carries a `werte_relevanz` map that indicates
which axes are relevant and in which direction:

```json
{
  "wirtschaft": 0.8,
  "diplomatie": 0.0,
  "freiheit": -0.5,
  "wandel": 0.6
}
```

Positive values mean the action is oriented toward the positive pole of
the axis. Negative toward the negative pole.

The werte match score for a user-action pair:

```dart
double werteMatch(Action action, ValueProfile profile) {
  double score = 0;
  int count = 0;

  final axes = {
    'wirtschaft': profile.axisWirtschaft,
    'diplomatie': profile.axisDiplomatie,
    'freiheit': profile.axisFreiheit,
    'wandel': profile.axisWandel,
  };

  action.werteRelevanz.forEach((axis, relevance) {
    if (relevance == 0) return;
    final userScore = axes[axis] ?? 0.0;
    if (userScore == 0) return; // neutral user: no contribution
    // Alignment: same sign = positive match, opposite = negative
    score += (userScore * relevance).clamp(-1.0, 1.0);
    count++;
  });

  if (count == 0) return 0.5; // No relevant axes: neutral match
  return ((score / count) + 1) / 2; // Normalise to 0.0–1.0
}
```

A user who is strongly market-oriented (axisWirtschaft = +2) will score
high on actions where `werte_relevanz.wirtschaft > 0` and low on actions
where `werte_relevanz.wirtschaft < 0`. A neutral user (0) gets a
neutral match (0.5) regardless of action orientation.

---

## Letter Tone Derivation

Before calling the letter generation endpoint, the app maps axis scores
to descriptive tone strings. These strings are sent to the backend instead
of raw scores.

```dart
List<String> deriveToneDescriptors(ValueProfile profile) {
  final descriptors = <String>[];

  if (profile.axisWirtschaft < -0.5)
    descriptors.add('community-oriented');
  if (profile.axisWirtschaft > 0.5)
    descriptors.add('pragmatic');

  if (profile.axisDiplomatie < -0.5)
    descriptors.add('nationally-focused');
  if (profile.axisDiplomatie > 0.5)
    descriptors.add('internationally-minded');

  if (profile.axisFreiheit < -0.5)
    descriptors.add('rights-conscious');
  if (profile.axisFreiheit > 0.5)
    descriptors.add('security-oriented');

  if (profile.axisWandel < -0.5)
    descriptors.add('stability-oriented');
  if (profile.axisWandel > 0.5)
    descriptors.add('reform-minded');

  if (descriptors.isEmpty) descriptors.add('balanced');
  return descriptors;
}
```

Example output: `["community-oriented", "reform-minded"]`

These strings are sent to the backend in the letter generation request.
Raw scores (-2 to +2) are never transmitted.

---

## Mistral Prompt Integration

The backend includes tone descriptors in the Mistral prompt:

```python
f"""Write a letter in German from a citizen with the following orientation:
{', '.join(tone_descriptors)}.
Do not mention political parties. Do not state opinions directly.
Express concern and ask for action. Max 180 words."""
```

---

## Profile Completeness

The app tracks how many questions were answered (non-zero):

```dart
int get answeredCount => [
  wirtschaft_gleichheit, wirtschaft_staat,
  diplomatie_nation, diplomatie_welt,
  freiheit_staat, freiheit_sicherheit,
  wandel_tradition, wandel_zukunft,
].where((v) => v != 0).length;

bool get isMinimallyComplete => answeredCount >= 4;
bool get isFullyComplete => answeredCount == 8;
```

If `answeredCount < 4`, the feed scoring falls back to topic-only matching
(werte match = 0.5 for all actions). A soft prompt in settings suggests
completing the profile.

---

## No Werte Match When Position is Ambiguous

If an action's `werte_relevanz` map is empty (no clear axis orientation),
the werte match defaults to 0.5 (neutral). This covers non-partisan
procedural actions like "Request information from your MdB about X".

---

## Dependencies

- Reads: `architecture/dsgvo.md`, `user/onboarding.md`
- Referenced by: `features/feed.md`, `features/letter-generation.md`

---

## Open Questions

- None.
