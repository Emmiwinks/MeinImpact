# Feed

## Purpose
Defines how the personalized action feed is assembled, scored, and
displayed. All scoring runs on the device. The backend serves a static
pool.

---

## Decisions

- **Feed scoring is entirely client-side.** The backend serves the same
  pool to every device. No server-side personalisation.

- **Feed refreshes on every app start** if the pool version has changed.
  Within a session, the feed is static (no pull-to-refresh in MVP).

- **No hardcoded maximum on feed size.** All actions that pass the
  relevance threshold (score ≥ 0.2) are shown. The app tracks which
  actions the user has completed or dismissed this week and filters
  them out. In practice the pool size (≤ 100 active actions) and the
  relevance threshold naturally limit the feed to a manageable number.

- **No topic filtering.** The feed shows all actions from the pool,
  ranked purely by value alignment and urgency. There is no topic
  whitelist or blacklist — users see every action the pipeline surfaces,
  scored by how well it matches their political values.

- **Actions where `position_required=true` and user has no clear position
  are shown but letter generation is suppressed.** The action appears in
  the feed with pro/contra arguments but without a pre-drafted letter.

---

## Scoring Algorithm

Each action receives a final score computed locally:

```dart
double scoreAction(Action action, UserProfile profile) {
  // 1. Hard exclusions
  if (completedThisWeek.contains(action.id)) return -1;
  if (dismissedThisWeek.contains(action.id)) return -1;

  // 2. Werte match (0.0–1.0) — see user/value-profile.md
  final werteMatch = computeWerteMatch(action, profile.werte);

  // 3. Urgency score (0.0–1.0)
  final urgencyScore = switch (action.urgency) {
    'high' => 1.0,
    'mid'  => 0.6,
    _      => 0.3,
  };

  // 4. Deadline proximity bonus (0.0–0.4)
  final deadlineBonus = action.deadline == null ? 0.0 :
      (1.0 - (action.deadline!.difference(DateTime.now()).inDays / 60.0))
      .clamp(0.0, 0.4);

  // 5. Momentum (from pipeline: beratungsstand imminence + petition velocity)
  final momentumBonus = action.momentumScore * 0.1;

  // Final score
  return werteMatch * 0.60 +
         urgencyScore * 0.25 +
         deadlineBonus * 0.10 +
         momentumBonus * 0.05;
}
```

**Score weight rationale:**
- Werte match (60%): primary signal — how well the action aligns with the
  user's political values. With no topic filtering, this is the main
  personalisation dimension.
- Urgency (25%): time-sensitive actions are prioritised regardless of values.
- Deadline proximity (10%): fine-grained urgency within the same urgency tier.
- Momentum (5%): slight boost for actions with high parliamentary imminence
  or fast petition velocity.

---

## Feed Assembly

```dart
List<FeedItem> assembleFeed(List<Action> pool, UserProfile profile) {
  // Score all actions, show all above threshold
  return pool
    .map((a) => (action: a, score: scoreAction(a, profile)))
    .where((item) => item.score >= 0.2)  // Relevance threshold
    .sortedByDescending((item) => item.score)
    .toList();
  // No hardcoded limit — the pool size (≤ 100) and threshold
  // naturally constrain the feed to a manageable number.
}
```

---

## Feed Item Display

Each feed card shows:

```
┌─────────────────────────────────────────────┐
│ [Tag: Brief / Petition / Anfrage]   [Dringlichkeit-Dot] │
│                                                          │
│ Titel der Aktion (max. 2 Zeilen)                        │
│                                                          │
│ ● Zeitindikator      ● ~X Min                           │
│                                                          │
│ ●●●●○  Relevanz für dich                                │
└─────────────────────────────────────────────┘
```

**Dringlichkeit indicator:**
- 🔴 Red dot: urgency=high (deadline within 14 days or vote scheduled)
- 🟡 Yellow dot: urgency=mid
- 🟢 Green dot: urgency=low

**Relevanz dots:** 5-dot display derived from final score:
- score ≥ 0.8: 5 dots
- score ≥ 0.6: 4 dots
- score ≥ 0.4: 3 dots
- score ≥ 0.2: 2 dots
- score < 0.2: 1 dot

**Letter-suppressed card:** If `position_required=true` and user has no
clear position: normal card, but action detail shows pro/contra only,
no letter button.

---

## Weekly Reset

The app tracks dismissed and completed actions per week:

```dart
// In Hive gamification box
Map<String, List<String>> weeklyState = {
  'completed': [],   // action IDs completed this week
  'dismissed': [],   // action IDs dismissed this week
};

// Reset on Monday 00:00 local time
void checkWeeklyReset() {
  final lastReset = Hive.box('gamification').get('last_weekly_reset');
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final weekStart = DateTime(monday.year, monday.month, monday.day);
  if (lastReset == null || DateTime.parse(lastReset).isBefore(weekStart)) {
    Hive.box('gamification').put('completed_this_week', []);
    Hive.box('gamification').put('dismissed_this_week', []);
    Hive.box('gamification').put('last_weekly_reset',
        weekStart.toIso8601String());
  }
}
```

---

## Dismiss Behaviour

Users can dismiss an action from the feed with a swipe or long-press.
Dismissed actions:
- Are hidden for the current week
- Are not counted toward the streak
- Are not marked as completed
- Appear again next week if still in the pool

No negative feedback is recorded. Dismissal is local only.

---

## Empty Feed State

If fewer than 1 action passes scoring (unlikely but possible):

*"Diese Woche gibt es keine neuen Aktionen. Schau nächste Woche wieder
vorbei — die Aktionen werden täglich aktualisiert."*

---

## Accessibility

- Each card: full Semantics label including title, type, urgency, and time
- Swipe-to-dismiss: also available via long-press menu for switch access
- Colour is not the only indicator: urgency dot has text equivalent
- Relevance dots: labelled as "Relevanz: X von 5" for screenreader

---

## Localisation

All strings in `l10n/`. Urgency labels, card tags, and empty states are
fully localised.

---

## Dependencies

- Reads: `architecture/data-flow.md`, `user/value-profile.md`,
  `user/general-profile.md`, `data/caching.md`
- Referenced by: `features/action-types.md`, `technical/local-storage.md`

---

## Open Questions

- None.
