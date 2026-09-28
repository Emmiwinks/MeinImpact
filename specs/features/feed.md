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

Each action carries an `engagement_state` (`A` | `B` | `C`) assigned by
the ingestion pipeline — see `data/ingestion-pipeline.md`. This state,
not a weighted hotness score, is the primary sort key. Actions are
sorted in three tiers, and only within a tier does werte alignment and
deadline proximity break ties:

```dart
(int, double, int) sortKey(Action action, UserProfile profile) {
  // Hard exclusions handled separately — see assembleFeed below

  // 1. Primary: engagement state tier (A > B > C)
  final stateRank = switch (action.engagementState) {
    'A' => 3,
    'B' => 2,
    _   => 1,
  };

  // 2. Secondary: werte match (0.0–1.0) — see user/value-profile.md
  final werteMatch = computeWerteMatch(action, profile.werte);

  // 3. Tertiary: deadline proximity, only meaningful for state A
  final deadlineRank = action.engagementState == 'A' && action.deadline != null
      ? -action.deadline!.difference(DateTime.now()).inDays  // sooner = higher
      : 0;

  return (stateRank, werteMatch, deadlineRank);
}
```

**Sort rationale:**
- Engagement state (primary): whether there is a decision window (A), a
  positioning window (B), or a debate window (C) determines how
  actionable and time-sensitive an action genuinely is — this is a
  stronger relevance signal than any weighted composite score.
- Werte match (secondary): within the same state tier, actions that
  align with the user's political values surface first.
- Deadline proximity (tertiary, state A only): among multiple state-A
  actions, the one whose window closes soonest is prioritised.

**Relevance threshold** (below) is still computed from werte match alone
— it answers "is this action relevant to you at all", independent of
how urgent it is.

---

## Feed Assembly

```dart
List<FeedItem> assembleFeed(List<Action> pool, UserProfile profile) {
  final eligible = pool.where((a) =>
      !completedThisWeek.contains(a.id) &&
      !dismissedThisWeek.contains(a.id));

  return eligible
    .map((a) => (action: a, werteMatch: computeWerteMatch(a, profile.werte)))
    .where((item) => item.werteMatch >= 0.2)  // Relevance threshold
    .sortedBy((item) => sortKey(item.action, profile))  // descending
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
│ [Tag: Brief / Petition / Anfrage]                       │
│                                                          │
│ Titel der Aktion (max. 2 Zeilen)                        │
│                                                          │
│ ⏳ {state_reason}                                        │
│                                                          │
│ ● ~X Min                                                │
│                                                          │
│ ●●●●○  Relevanz für dich                                │
└─────────────────────────────────────────────┘
```

**Urgency label — status (2026-09-27): pending redesign.** The text below
described `state_reason`/`engagement_state` (A/B/C), which came from the
now-retired DIP-derived ingestion pipeline — see
`data/ingestion-pipeline.md` "Status". It's kept here as a reference for
the display pattern (a specific sentence beats a traffic-light dot) until
the new pipeline defines what replaces it; the concrete states (A/B/C) and
the MdB personalisation logic below should not be assumed to survive
as-is.

The `state_reason` text (server-generated, German, set by the ingestion
pipeline per `engagement_state`) was displayed directly on the card as the
urgency label, replacing a red/yellow/green urgency dot — a state-specific
sentence is more honest and more actionable than a traffic-light colour.
Examples:
- State A: "Abstimmung in 8 Tagen"
- State B: "An den Ausschuss überwiesen" (the concrete observed fact,
  not a generic claim)
- State C: "Wird gerade breit diskutiert"

A small icon accompanied the state tier for quick scanning (state A:
⏳, state B: 💬, state C: 📣), but the text itself — not the icon colour —
carried the meaning, per the accessibility rule that colour is never the
only indicator.

**Client-side state-B personalisation (retired along with state B):**
`state_reason` for a state-B action was action-level and identical for
every user — it came from a DIP signal, not a per-MdB check. Before
rendering a state-B card, the app checked the cached Abgeordnetenwatch
answer history for the user's own MdB (`profile.mdb` in Hive, refreshed
every 30 days per `data/sources-federal.md` Source 3). If that MdB had
already answered a question on this topic, the displayed label was
overridden locally to *"[MdB Name] hat sich bereits geäußert — schreib
trotzdem"*. This was a display-only override: the underlying
`engagement_state` and its contribution to sort order were unchanged, and
no other user's view of the same action was affected. This mechanism has
no state-B to attach to anymore; revisit once the new pipeline design
lands.

**Relevanz dots:** 5-dot display derived from werte match:
- match ≥ 0.8: 5 dots
- match ≥ 0.6: 4 dots
- match ≥ 0.4: 3 dots
- match ≥ 0.2: 2 dots
- match < 0.2: 1 dot

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

- Each card: full Semantics label including title, type, `state_reason`,
  and time
- Swipe-to-dismiss: also available via long-press menu for switch access
- Colour is not the only indicator: the state icon always has the
  `state_reason` text alongside it
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
