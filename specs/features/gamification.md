# Gamification

## Purpose
Defines the streak, badge, and progress systems that motivate continued
engagement. All gamification state is stored locally on the device.

---

## Decisions

- **All gamification state is local.** Streak, badges, and action history
  are in Hive. The server never receives or stores this data.

- **Weekly cadence, not daily.** One meaningful action per week is the
  target. Daily streaks would create pressure that undermines the
  quality-over-quantity goal.

- **Streaks measure consistency, not volume.** A week counts if at least
  one action was completed. Completing multiple actions in a week
  counts the same as completing 1.

- **Badges are milestone-based, not activity-based.** They reflect
  meaningful thresholds, not mere usage frequency.

- **No social comparison.** No leaderboards, no "you're in the top X%"
  comparisons with other users in MVP. The app shows only the user's
  own history.

- **Gamification never pressures.** No "your streak will break tomorrow"
  warnings. No guilt mechanics. The app celebrates action; it does not
  punish inaction.

---

## Streak System

### Definition
A streak is the number of consecutive calendar weeks in which the user
completed at least one civic action.

### Storage
```dart
// Hive gamification box
{
  'current_streak': 4,           // consecutive weeks
  'longest_streak': 7,
  'last_action_week': '2026-W23', // ISO week string
  'total_actions': 12,
}
```

### Streak update logic
```dart
void updateStreak() {
  final now = DateTime.now();
  final thisWeek = isoWeekString(now);          // e.g. "2026-W23"
  final lastWeek = isoWeekString(now.subtract(const Duration(days: 7)));
  final box = Hive.box('gamification');
  final lastActionWeek = box.get('last_action_week');

  if (lastActionWeek == thisWeek) {
    // Already completed an action this week — no change needed
    return;
  }

  if (lastActionWeek == lastWeek) {
    // Consecutive week — increment streak
    final current = box.get('current_streak', defaultValue: 0) + 1;
    box.put('current_streak', current);
    box.put('longest_streak',
        max(current, box.get('longest_streak', defaultValue: 0)));
  } else {
    // Gap in weeks — reset streak to 1
    box.put('current_streak', 1);
  }

  box.put('last_action_week', thisWeek);
  box.put('total_actions',
      box.get('total_actions', defaultValue: 0) + 1);
}
```

### Streak display on confirmation screen
```
┌─────────────────────────────────────────────┐
│           🔥  5  Wochen in Folge            │
│        Du bleibst am Ball.                  │
└─────────────────────────────────────────────┘
```

Streak of 1: "Dein erster Beitrag diese Woche."
Streak of 2–4: "{n} Wochen in Folge."
Streak ≥ 5: "{n} Wochen in Folge. 🔥"
Streak ≥ 12: "{n} Wochen in Folge. Das ist ein Vierteljahr. 🌱"
Streak ≥ 52: "{n} Wochen in Folge. Ein ganzes Jahr. 🦋"

No "streak broken" message is ever shown. Broken streaks are
simply reset silently. The app only celebrates, never shames.

---

## Badge System

Badges are awarded locally when thresholds are crossed. They are
displayed in Settings → Meine Aktivität.

### Badge definitions

| Badge | Condition | Icon |
|---|---|---|
| Erster Schritt | First action completed | 🌱 |
| Drei Wochen | 3-week streak | 🔥 |
| Sechs Wochen | 6-week streak | 🔥🔥 |
| Quartal | 12-week streak | 📅 |
| Halbjahr | 26-week streak | 🌿 |
| Ein Jahr | 52-week streak | 🦋 |
| Brief-Schreiber | 5 letters sent | ✉️ |
| Petitions-Unterstützer | 5 petitions signed | 📝 |
| Fragesteller | 3 public questions asked | ❓ |
| Themenvielfalt | Actions in 3 different topics | 🗺️ |
| Ergebnis-Tracker | First tracking event received | 🔔 |
| Hartnäckig | Action completed in 3 consecutive weeks on same topic | 💪 |

### Badge award logic
```dart
void checkBadges(Gamification state) {
  final box = Hive.box('gamification');
  final earned = Set<String>.from(box.get('badges', defaultValue: []));

  void award(String badge) {
    if (!earned.contains(badge)) {
      earned.add(badge);
      box.put('badges', earned.toList());
      // Trigger badge award animation on confirmation screen
      box.put('pending_badge', badge);
    }
  }

  if (state.totalActions >= 1) award('erster_schritt');
  if (state.currentStreak >= 3) award('drei_wochen');
  if (state.currentStreak >= 6) award('sechs_wochen');
  if (state.currentStreak >= 12) award('quartal');
  if (state.currentStreak >= 26) award('halbjahr');
  if (state.currentStreak >= 52) award('ein_jahr');
  if (state.letterCount >= 5) award('brief_schreiber');
  if (state.petitionCount >= 5) award('petitions_unterstuetzer');
  if (state.anfrageCount >= 3) award('fragesteller');
  if (state.uniqueTopics.length >= 3) award('themenvielfalt');
  if (state.hasReceivedTrackingEvent) award('ergebnis_tracker');
}
```

### Badge display on confirmation screen
When a new badge is earned, it appears on the confirmation screen
with a subtle animation:

```
┌─────────────────────────────────────────────┐
│  ✨ Neue Auszeichnung                        │
│  📝  Petitions-Unterstützer                 │
│  Du hast 5 Petitionen unterstützt.          │
└─────────────────────────────────────────────┘
```

Only one badge announcement per session. Multiple new badges are
queued and shown one at a time.

---

## Impact Counter

Shown on confirmation screen and tracking detail:

```
Du warst eine von 1.247 Personen die diese Woche aktiv wurden.
```

This number comes from `action_stats.completion_count` fetched from
the backend. It is anonymous (no individual breakdown).

Purpose: social proof without social pressure. The user sees they are
part of a larger movement without being ranked within it.

---

## Progress Indicators on Feed Screen

Small streak indicator in feed header:

```
┌──────────────────────────────────────────────┐
│ Guten Morgen          🔥 4 Wochen aktiv      │
│ 3 Empfehlungen für dich                      │
└──────────────────────────────────────────────┘
```

Streak is shown only if ≥ 2 weeks. Below 2 weeks: no indicator shown
(avoids early pressure).

---

## Activity Screen

Accessible from Settings → Meine Aktivität.

```
MEINE AKTIVITÄT

Aktionen gesamt: 12
Längste Serie: 7 Wochen
Aktuelle Serie: 4 Wochen

AUSZEICHNUNGEN
🌱 Erster Schritt      ✉️ Brief-Schreiber
📝 Petitions-Unter.   🔔 Ergebnis-Tracker
🔥 Drei Wochen

AKTIONSVERLAUF
● Brief: Solaranlagen (15. Apr)  🟢
● Petition: Lobbyregister (8. Apr) ⏳
● Brief: Pflegefinanzierung (1. Apr) 🟢
[Alle anzeigen →]
```

---

## Localisation

All strings localised. Streak milestone messages have gender-neutral
formulations. Badge names are in German only (no English fallback needed).

---

## Accessibility

- Badge animations respect reduced-motion system setting
- All badges have text descriptions for screenreader
- Streak number is announced to screenreader on confirmation screen

---

## Dependencies

- Reads: `features/action-types.md`, `features/tracking.md`,
  `technical/local-storage.md`
- Referenced by: `technical/local-storage.md`

---

## Open Questions

- None.
