import '../../feed/data/opportunity_relevance_ranker.dart';
import '../../feed/domain/interest_config.dart';
import '../../feed/domain/lebenslage.dart';
import '../../feed/domain/opportunity.dart';
import '../../feed/domain/user_profile.dart';
import '../../tracking/domain/action_log.dart';
import '../../tracking/domain/impact_news.dart';
import '../../tracking/domain/progress.dart';
import 'notification_state.dart';
import 'notification_texts.dart';

/// Nothing is shown from [kQuietFrom] o'clock until [kQuietUntil].
const kQuietFrom = 21;
const kQuietUntil = 8;

/// At most this many notifications a day and a week (Monday to Sunday);
/// results don't count.
const kMaxPerDay = 1;
const kMaxPerWeek = 3;

/// At most one deadline reminder a week.
const kMaxDeadlinesPerWeek = 1;

/// Notifications are planned this far ahead; the next check plans further.
const kPlanAhead = Duration(days: 8);

/// The hours scheduled notifications come at.
const kFlameHour = 17;
const kDecisionHour = 18;
const kTookPartHour = 19;
const kWeekHour = 9;
const kDeadlineHour = 9;

/// Deadline reminders come this many days before a card closes.
const kDeadlineDaysBefore = 2;

/// Cards looked at are forgotten after this long.
const kLookedAtKept = Duration(days: 21);

/// Shown keys are kept this long, long enough to never repeat one.
const kShownKept = Duration(days: 35);

/// "Abgeschickt?" the evening after leaving a site without "Fertig". Off
/// for the beta (user decision 2026-11-21: may feel pushy).
const kAskIfTookPart = false;

/// What one check does: show some now, schedule others, cancel what is no
/// longer wanted, and remember it all in [state].
class NotificationPlan {
  const NotificationPlan({
    required this.show,
    required this.schedule,
    required this.cancel,
    required this.state,
  });

  final List<PlannedNotification> show;
  final List<PlannedNotification> schedule;
  // System ids of scheduled notifications to drop.
  final List<int> cancel;
  final NotificationState state;
}

/// Decides what to notify about, everything matched on the device: the
/// server only ever hands out the same pool and news to everyone.
///
/// [pool] and [news] are null when they could not be (or were not)
/// loaded; Monday's notification then stays as planned before, and
/// results and news wait for the next check. [off] are the channels the
/// user switched off in Android.
NotificationPlan planNotifications({
  required DateTime now,
  required NotificationState state,
  required ActionLog log,
  required Set<String> starred,
  required UserProfile profile,
  Set<NotificationChannel> off = const {},
  List<Opportunity>? pool,
  ImpactNewsFeed? news,
  InterestConfig interestConfig = const InterestConfig(),
  bool askIfTookPart = kAskIfTookPart,
}) {
  final poolById = {for (final o in pool ?? const <Opportunity>[]) o.id: o};

  // Whether an action concerns a private Lebenslage; unknown counts as yes.
  bool isPrivate(ActionLogEntry entry) {
    final lebenslagen =
        entry.lebenslagen ?? poolById[entry.opportunityId]?.lebenslagen;
    return lebenslagen == null || lebenslagen.any(_isPrivateLebenslage);
  }

  String? nameOf(ActionLogEntry entry) => isPrivate(entry) ? null : entry.title;

  // Scheduled ones that came due have been shown by the system.
  final shown = <String, DateTime>{
    for (final MapEntry(:key, :value) in state.shown.entries)
      if (now.difference(value) < kShownKept) key: value,
    for (final p in state.planned)
      if (!p.at.isAfter(now)) p.key: p.at,
  };
  final lookedAt = {
    for (final MapEntry(:key, :value) in state.lookedAt.entries)
      if (!log.isDone(key) && now.difference(value.at) < kLookedAtKept)
        key: value,
  };
  final newsSeen = {
    for (final MapEntry(:key, :value) in state.newsSeen.entries)
      if (starred.contains(key)) key: value,
  };

  final candidates = <PlannedNotification>[];
  PlannedNotification make(
    NotificationKind kind,
    String what,
    DateTime at,
    NotificationText text, {
    String? opportunityId,
  }) =>
      PlannedNotification(
        key: '${kind.wire}:$what',
        kind: kind,
        at: at,
        title: text.title,
        body: text.body,
        opportunityId: opportunityId,
      );

  // Petitions whose goal was reached after the user signed.
  for (final entry in log.entries) {
    final goal = entry.supportGoal;
    final count = poolById[entry.opportunityId]?.supportCount;
    if (entry.kind != OpportunityKind.petition ||
        goal == null ||
        (entry.supportCount ?? goal) >= goal ||
        count == null ||
        count < goal ||
        !_awake(now)) {
      continue;
    }
    candidates.add(
      make(
        NotificationKind.result,
        entry.opportunityId,
        now,
        resultText(nameOf(entry)),
        opportunityId: entry.opportunityId,
      ),
    );
  }

  // Council votes the user wrote about, the evening before.
  for (final entry in log.entries) {
    final day = entry.closesOn;
    if (entry.kind != OpportunityKind.decision || day == null) continue;
    final wanted = _at(_dayOf(day, -1), kDecisionHour);
    final at = _when(wanted, now);
    // Not right after writing the letter that same evening.
    if (at == null || !entry.doneAt.isBefore(wanted)) continue;
    candidates.add(
      make(
        NotificationKind.decision,
        entry.opportunityId,
        at,
        decisionText(nameOf(entry)),
        opportunityId: entry.opportunityId,
      ),
    );
  }

  // New reports on starred actions, all in one notification.
  final fresh = <ActionLogEntry, List<ImpactNewsItem>>{};
  if (news != null) {
    for (final entry in log.entries) {
      final id = entry.opportunityId;
      if (!starred.contains(id)) continue;
      final items = [
        for (final item in news[id]?.items ?? const <ImpactNewsItem>[])
          if (!item.isBackground && item.url.isNotEmpty) item,
      ];
      final seen = newsSeen[id];
      if (seen == null) {
        newsSeen[id] = {for (final item in items) item.url};
        continue;
      }
      final unseen = [
        for (final item in items)
          if (!seen.contains(item.url)) item,
      ];
      if (unseen.isNotEmpty) fresh[entry] = unseen;
    }
  }
  if (fresh.isNotEmpty && _awake(now)) {
    final urls = [
      for (final items in fresh.values)
        for (final item in items) item.url,
    ]..sort();
    final single = fresh.length == 1 ? fresh.keys.single : null;
    candidates.add(
      make(
        NotificationKind.news,
        _hash(urls.join(' ')),
        now,
        newsText(
          [for (final entry in fresh.keys) nameOf(entry)],
          [for (final item in fresh.values.first) item.title],
        ),
        opportunityId: single?.opportunityId,
      ),
    );
  }

  // The flame goes out at midnight unless the user acts this week.
  final streak = Progress.of(log, now).streak;
  if (streak.state == StreakState.paused) {
    final monday = _monday(now);
    final at = _when(_at(_dayOf(monday, 6), kFlameHour), now);
    if (at != null) {
      candidates.add(
        make(
          NotificationKind.flame,
          _isoDay(monday),
          at,
          flameText(_weekNumber(monday), streak.weeks),
        ),
      );
    }
  }

  for (final looked in lookedAt.values) {
    final card = looked.card;
    // Two days before a card looked at earlier closes.
    if (card.closesOn case final closes?) {
      final wanted = _at(_dayOf(closes, -kDeadlineDaysBefore), kDeadlineHour);
      final at = _when(wanted, now);
      if (at != null && looked.at.isBefore(wanted)) {
        candidates.add(
          make(
            NotificationKind.deadline,
            card.opportunityId,
            at,
            deadlineText(nameOf(card), kDeadlineDaysBefore),
            opportunityId: card.opportunityId,
          ),
        );
      }
    }
    // The evening after leaving its site without "Fertig".
    if (askIfTookPart && looked.openedSite) {
      final at = _when(_at(_dayOf(looked.at, 1), kTookPartHour), now);
      if (at != null) {
        candidates.add(
          make(
            NotificationKind.tookPart,
            card.opportunityId,
            at,
            tookPartText(nameOf(card)),
            opportunityId: card.opportunityId,
          ),
        );
      }
    }
  }

  // Monday morning, unless the app was already open that Monday.
  final opened = state.lastOpenedAt;
  var monday = _monday(now);
  if (!_at(monday, kWeekHour).isAfter(now) ||
      (opened != null && !opened.isBefore(monday))) {
    monday = _dayOf(monday, 7);
  }
  // Kept apart from what is scheduled, so it survives a day the limits or
  // a switched-off channel left it out.
  PlannedNotification? week;
  if (pool == null) {
    final before = state.week;
    if (before != null && _day(before.at) == monday) week = before;
  } else {
    final since = _dayOf(monday, -7);
    final fits = [
      for (final ranked in OpportunityRelevanceRanker(
        interestConfig: interestConfig,
      ).rank(pool, profile, now: now))
        if (!ranked.opportunity.firstSeenAt.isBefore(since) &&
            !log.isDone(ranked.opportunity.id) &&
            (ranked.isSituationMatch || ranked.interestTag != null))
          ranked.opportunity,
    ];
    if (fits.isNotEmpty) {
      final best = fits.first;
      week = make(
        NotificationKind.week,
        _isoDay(monday),
        _at(monday, kWeekHour),
        weekText(
          _weekNumber(monday),
          fits.length,
          best.lebenslagen.any(_isPrivateLebenslage) ? null : best.title,
        ),
      );
    }
  }
  if (week != null) candidates.add(week);

  // Most important first; each takes its day while the limits allow.
  candidates
    ..removeWhere(
      (c) =>
          off.contains(c.kind.channel) ||
          shown.containsKey(c.key) ||
          c.at.difference(now) > kPlanAhead,
    )
    ..sort((a, b) {
      final byKind = a.kind.index.compareTo(b.kind.index);
      return byKind != 0 ? byKind : a.at.compareTo(b.at);
    });
  final taken = <(NotificationKind, DateTime)>[
    for (final MapEntry(:key, :value) in shown.entries)
      if (NotificationKind.ofKey(key) case final kind?) (kind, value),
  ];
  final accepted = <PlannedNotification>[];
  for (final c in candidates) {
    if (accepted.any((a) => a.key == c.key)) continue;
    if (!c.kind.exempt) {
      final sameDay = taken.where(
        (t) => !t.$1.exempt && _day(t.$2) == _day(c.at),
      );
      final sameWeek = taken.where(
        (t) => !t.$1.exempt && _monday(t.$2) == _monday(c.at),
      );
      if (sameDay.length >= kMaxPerDay ||
          sameWeek.length >= kMaxPerWeek ||
          (c.kind == NotificationKind.deadline &&
              sameWeek.where((t) => t.$1 == NotificationKind.deadline).length >=
                  kMaxDeadlinesPerWeek)) {
        continue;
      }
    }
    accepted.add(c);
    taken.add((c.kind, c.at));
  }

  final show = [
    for (final c in accepted)
      if (!c.at.isAfter(now)) c,
  ];
  final schedule = [
    for (final c in accepted)
      if (c.at.isAfter(now)) c,
  ];
  for (final c in show) {
    shown[c.key] = now;
    if (c.kind == NotificationKind.news) {
      fresh.forEach((entry, items) {
        newsSeen[entry.opportunityId] = {
          ...?newsSeen[entry.opportunityId],
          for (final item in items) item.url,
        };
      });
    }
  }
  final keep = {for (final c in schedule) c.key};
  return NotificationPlan(
    show: show,
    schedule: schedule,
    cancel: [
      for (final p in state.planned)
        if (p.at.isAfter(now) && !keep.contains(p.key)) p.id,
    ],
    state: NotificationState(
      shown: shown,
      planned: schedule,
      week: week,
      newsSeen: newsSeen,
      lookedAt: lookedAt,
      lastOpenedAt: state.lastOpenedAt,
      poolFetchedAt: state.poolFetchedAt,
    ),
  );
}

bool _isPrivateLebenslage(String id) => lebenslageById[id]?.isPrivate ?? false;

bool _awake(DateTime t) => t.hour >= kQuietUntil && t.hour < kQuietFrom;

/// When a notification wanted at [wanted] comes: then, or right now if
/// that has passed earlier today and it is not quiet time yet (the check
/// that would have planned it ran late). Null once it is too late.
DateTime? _when(DateTime wanted, DateTime now) {
  if (wanted.isAfter(now)) return wanted;
  return _day(wanted) == _day(now) && _awake(now) ? now : null;
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

// Calendar arithmetic by date, so a daylight saving switch never shifts it.
DateTime _dayOf(DateTime t, int days) =>
    DateTime(t.year, t.month, t.day + days);

DateTime _at(DateTime day, int hour) =>
    DateTime(day.year, day.month, day.day, hour);

DateTime _monday(DateTime t) => _dayOf(t, -(t.weekday - 1));

// Weeks since a Monday (2024-01-01 was one), counted on UTC dates.
int _weekNumber(DateTime monday) =>
    DateTime.utc(monday.year, monday.month, monday.day)
        .difference(DateTime.utc(2024, 1, 1))
        .inDays ~/
    7;

String _isoDay(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

String _hash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16);
}
