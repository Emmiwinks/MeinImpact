import '../../feed/domain/topic_tags.g.dart';
import 'action_log.dart';

/// Streak, milestones and topic badges. All of it follows from the action
/// log on the device, so nothing new is stored or sent anywhere.

/// Full weeks without an action that only pause a streak; one more and it
/// ends. Civic actions don't come every week, and holidays happen.
const kStreakPauseWeeks = 1;

/// Days since the last action up to which the flame burns strong, then
/// medium; after that only an ember glows. For people who look in daily,
/// the flame shows how fresh the last action is within the week.
const kFlameStrongDays = 2;
const kFlameMediumDays = 6;

/// The track over all topics: total counts of done actions, as instruments
/// from a squeak to a roar, since every action makes the user's voice
/// louder. Never tied to the hand: playing all five cards is not a goal.
const kMilestones = <Milestone>[
  Milestone(1, 'Kazoo'),
  Milestone(3, 'Trillerpfeife'),
  Milestone(5, 'Tröte'),
  Milestone(10, 'Trompete'),
  Milestone(25, 'Posaune'),
  Milestone(50, 'Pauke'),
  Milestone(100, 'Kirchenorgel'),
];

/// The track per topic: actions in one topic for each badge tier.
const kBadgeTiers = [3, 10, 25];

/// Three names per topic, one per tier: things, never people, so no name
/// needs gendering.
const kBadgeNames = <String, List<String>>{
  'Wohnen/Miete': ['Mietzekatze', 'Klingelschild', 'Schlüsselbund'],
  'Mobilität/Verkehr': ['Bimmelbahn', 'Lastenrad', 'Doppeldeckerbus'],
  'Arbeit/Einkommen': ['Kaffeekasse', 'Stempelkarte', 'Chefsessel'],
  'Energie/Heizkosten': ['Wollsocke', 'Wärmflasche', 'Windrad'],
  'Bildung/Ausbildung': ['Eselsohr', 'Tafelschwamm', 'Bücherwurm'],
  'Rente/Alter': ['Lesebrille', 'Ohrensessel', 'Silberlocke'],
  'Digitales/Datenschutz': ['Passwort123', 'Cookie-Monster', 'Supercomputer'],
  'Sicherheit': ['Nachtlicht', 'Schutzengel', 'Leuchtturm'],
  'Migration/Integration': ['Wörterbuch', 'Lange Tafel', 'Festzelt'],
  'Außenpolitik/Verteidigung': ['Schneekugel', 'Reisepass', 'Friedenstaube'],
  'Demokratie/Mitbestimmung': ['Kreuzchen', 'Megafon', 'Rednerpult'],
  'Stadtentwicklung/Bauen': ['Bauklotz', 'Betonmischer', 'Riesenkran'],
  'Gesundheit/Pflege': ['Hühnersuppe', 'Obstkorb', 'Goldene Hantel'],
  'Familie/Kinder': ['Schnuller', 'Bobbycar', 'Hüpfburg'],
  'Umwelt/Natur': ['Regenwurm', 'Komposthaufen', 'Mammutbaum'],
  'Selbstständigkeit/Unternehmertum': [
    'Visitenkarte',
    'Registrierkasse',
    'Unicorn',
  ],
  'Gleichstellung/Inklusion': ['Wippe', 'Hebebühne', 'Regenbogen'],
};

class Milestone {
  const Milestone(this.count, this.title);

  final int count;
  final String title;

  /// The sticker, from tool/badges/build.mjs.
  String get asset => 'assets/badges/alle-${kMilestones.indexOf(this) + 1}.svg';
}

/// The sticker file name part for a topic tag: its first part, lower case,
/// ASCII (the same rule as tool/badges/build.mjs).
String topicSlug(String tag) => tag
    .split('/')
    .first
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss');

/// One sticker in the album, in the order the user earned them.
class EarnedSticker {
  const EarnedSticker({required this.asset, required this.title, this.tier});

  final String asset;
  final String title;

  /// The tier for a topic sticker; null on the track over all topics.
  final int? tier;
}

enum StreakState {
  /// No streak running.
  none,

  /// An action this week.
  active,

  /// None yet this week, but last week had one.
  open,

  /// A full week missed, still within [kStreakPauseWeeks].
  paused,
}

/// How the streak's flame looks.
enum FlameLevel {
  /// No streak: cold wood.
  out,

  /// Paused: the wood with a wisp of smoke.
  smoke,

  /// The last action is more than [kFlameMediumDays] days ago.
  ember,
  medium,
  strong,
}

class Streak {
  const Streak(
    this.weeks,
    this.state, {
    this.recent = const [],
    this.flame = FlameLevel.out,
  });

  /// Weeks with at least one action; paused weeks don't count.
  final int weeks;
  final StreakState state;

  /// The last [kStreakTrail] weeks, oldest first, the current one last:
  /// true where the user did something.
  final List<bool> recent;
  final FlameLevel flame;

  bool get burns => flame.index >= FlameLevel.ember.index;
}

/// Weeks the streak's trail shows.
const kStreakTrail = 8;

/// One topic's badge: the tier reached (0 = none yet) and the way there.
class TopicBadge {
  const TopicBadge({required this.tag, required this.actions});

  final String tag;
  final int actions;

  int get tier => kBadgeTiers.where((needed) => actions >= needed).length;

  /// The name of the tier reached; null before the first.
  String? get name => tier == 0 ? null : kBadgeNames[tag]![tier - 1];

  /// Actions the next tier needs; null once the last is reached.
  int? get nextAt => tier < kBadgeTiers.length ? kBadgeTiers[tier] : null;

  /// The topic's short name: the part before the slash.
  String get topic => tag.split('/').first;

  /// What the tier reached took, e.g. "3 Aktionen zum Thema Familie".
  String get earnedFor => '${kBadgeTiers[tier - 1]} Aktionen zum Thema $topic';

  /// The sticker of the tier reached; before the first, the first one (shown
  /// greyed).
  String get asset =>
      'assets/badges/${topicSlug(tag)}-${tier == 0 ? 1 : tier}.svg';
}

class Progress {
  const Progress({
    required this.actions,
    required this.streak,
    required this.badges,
    this.earned = const [],
  });

  factory Progress.of(ActionLog log, DateTime now) {
    final perTag = <String, int>{};
    final earned = <EarnedSticker>[];
    // Oldest first, so the stickers come out in the order they were earned.
    for (final (i, entry) in log.entries.indexed) {
      for (final m in kMilestones) {
        if (m.count == i + 1) {
          earned.add(EarnedSticker(asset: m.asset, title: m.title));
        }
      }
      // An action about several topics counts for each.
      for (final tag in entry.affectedTags.toSet()) {
        final count = perTag[tag] = (perTag[tag] ?? 0) + 1;
        if (!kBadgeNames.containsKey(tag) || !kBadgeTiers.contains(count)) {
          continue;
        }
        final badge = TopicBadge(tag: tag, actions: count);
        earned.add(
          EarnedSticker(
            asset: badge.asset,
            title: badge.name!,
            tier: badge.tier,
          ),
        );
      }
    }
    return Progress(
      actions: log.entries.length,
      streak: _streak(log, now),
      badges: [
        for (final tag in kTopicTags)
          TopicBadge(tag: tag, actions: perTag[tag] ?? 0),
      ],
      earned: earned,
    );
  }

  final int actions;
  final Streak streak;

  /// Every topic in the taxonomy's order, with or without a badge.
  final List<TopicBadge> badges;

  /// Every sticker earned so far, oldest first.
  final List<EarnedSticker> earned;

  /// The last milestone reached; null before the first action.
  Milestone? get milestone {
    Milestone? reached;
    for (final m in kMilestones) {
      if (actions >= m.count) reached = m;
    }
    return reached;
  }

  /// The milestone after [milestone]; null after the last.
  Milestone? get nextMilestone {
    for (final m in kMilestones) {
      if (actions < m.count) return m;
    }
    return null;
  }
}

/// The badges one more done action brought, for the moment after "Fertig".
/// The streak has its own moment on the flame.
class ProgressMoment {
  const ProgressMoment({this.milestone, this.badges = const []});

  /// Null when no badge was earned.
  static ProgressMoment? between(Progress before, Progress after) {
    final milestone = after.milestone;
    final moment = ProgressMoment(
      milestone: milestone != null && milestone.count > before.actions
          ? milestone
          : null,
      badges: [
        for (var i = 0; i < after.badges.length; i++)
          if (after.badges[i].tier > before.badges[i].tier) after.badges[i],
      ],
    );
    return moment.isEmpty ? null : moment;
  }

  final Milestone? milestone;
  final List<TopicBadge> badges;

  bool get isEmpty => milestone == null && badges.isEmpty;
}

Streak _streak(ActionLog log, DateTime now) {
  final weeks = {for (final e in log.entries) _weekIndex(e.doneAt.toLocal())}
      .toList()
    ..sort();
  final current = _weekIndex(now);
  final recent = [
    for (var w = current - kStreakTrail + 1; w <= current; w++)
      weeks.contains(w),
  ];
  if (weeks.isEmpty) return Streak(0, StreakState.none, recent: recent);
  final missedSinceLast = current - weeks.last - 1;
  if (missedSinceLast > kStreakPauseWeeks) {
    return Streak(0, StreakState.none, recent: recent);
  }
  var count = 1;
  for (var i = weeks.length - 1; i > 0; i--) {
    if (weeks[i] - weeks[i - 1] - 1 > kStreakPauseWeeks) break;
    count++;
  }
  final state = switch (missedSinceLast) {
    -1 => StreakState.active,
    0 => StreakState.open,
    _ => StreakState.paused,
  };
  final last = log.entries
      .map((e) => e.doneAt.toLocal())
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final days = _dayIndex(now) - _dayIndex(last);
  final flame = state == StreakState.paused
      ? FlameLevel.smoke
      : days <= kFlameStrongDays
          ? FlameLevel.strong
          : days <= kFlameMediumDays
              ? FlameLevel.medium
              : FlameLevel.ember;
  return Streak(count, state, recent: recent, flame: flame);
}

// Days and weeks in the phone's calendar, counted on UTC dates so a
// daylight saving switch can't shift a day.
int _dayIndex(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day)
        .difference(DateTime.utc(2024, 1, 1))
        .inDays;

// Weeks since a Monday (2024-01-01 was one).
int _weekIndex(DateTime local) =>
    ((_dayIndex(local) - (local.weekday - 1)) / 7).floor();
