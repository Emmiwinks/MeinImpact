import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/topic_tags.g.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/progress.dart';

// A Wednesday; weeks below count back from its Monday.
final _now = DateTime(2026, 11, 18, 12);

var _ids = 0;

ActionLogEntry _done(DateTime at, [List<String> tags = const []]) =>
    ActionLogEntry(
      opportunityId: '${_ids++}',
      doneAt: at.toUtc(),
      via: ActionVia.inAppBrowser,
      title: 'Aktion',
      kind: OpportunityKind.petition,
      sourceOrg: 'Org',
      sourceUrl: 'https://example.org',
      affectedTags: tags,
    );

DateTime _weeksAgo(int weeks) => _now.subtract(Duration(days: 7 * weeks));

Streak _streak(List<int> weeksAgo) => Progress.of(
      ActionLog([for (final w in weeksAgo.reversed) _done(_weeksAgo(w))]),
      _now,
    ).streak;

void main() {
  group('streak', () {
    test('counts weeks with an action, not actions', () {
      final log = ActionLog([
        _done(_weeksAgo(1)),
        _done(_weeksAgo(1)),
        _done(_now),
      ]);
      final streak = Progress.of(log, _now).streak;
      expect(streak.weeks, 2);
      expect(streak.state, StreakState.active);
    });

    test('is open when last week had one and this week not yet', () {
      final streak = _streak([1, 2]);
      expect(streak.weeks, 2);
      expect(streak.state, StreakState.open);
    });

    test('a missed week pauses it without losing the count', () {
      final streak = _streak([2, 3, 4]);
      expect(streak.weeks, 3);
      expect(streak.state, StreakState.paused);
      expect(streak.flame, FlameLevel.smoke);
    });

    test('carries on across a pause', () {
      // Week 1 and 3 missed
      expect(_streak([0, 2, 4]).weeks, 3);
    });

    test('ends after two missed weeks in a row', () {
      final streak = _streak([3]);
      expect(streak.weeks, 0);
      expect(streak.state, StreakState.none);
      expect(streak.flame, FlameLevel.out);
      // And such a gap inside the history starts a new one
      expect(_streak([0, 3]).weeks, 1);
    });

    test('a week starts on Monday', () {
      final monday = DateTime(2026, 11, 16, 0, 30);
      final sunday = DateTime(2026, 11, 15, 23, 30);
      final streak = Progress.of(ActionLog([_done(sunday)]), monday).streak;
      expect(streak.state, StreakState.open);
    });

    test('the trail ends with this week', () {
      final recent = _streak([0, 2]).recent;
      expect(recent.length, kStreakTrail);
      expect(recent.sublist(kStreakTrail - 3), [true, false, true]);
    });

    test('the flame weakens with the days since the last action', () {
      FlameLevel flame(int daysAgo) => Progress.of(
            ActionLog([_done(_now.subtract(Duration(days: daysAgo)))]),
            _now,
          ).streak.flame;
      expect(flame(0), FlameLevel.strong);
      expect(flame(kFlameStrongDays), FlameLevel.strong);
      expect(flame(kFlameStrongDays + 1), FlameLevel.medium);
      expect(flame(kFlameMediumDays), FlameLevel.medium);
      expect(flame(kFlameMediumDays + 1), FlameLevel.ember);
    });
  });

  group('badges', () {
    test('an action counts for each of its topics, once', () {
      final log = ActionLog([
        for (var i = 0; i < 3; i++)
          _done(_now, ['Umwelt/Natur', 'Mobilität/Verkehr', 'Umwelt/Natur']),
      ]);
      final badges = {
        for (final b in Progress.of(log, _now).badges) b.tag: b,
      };
      expect(badges['Umwelt/Natur']!.actions, 3);
      expect(badges['Umwelt/Natur']!.name, 'Regenwurm');
      expect(badges['Umwelt/Natur']!.earnedFor, '3 Aktionen zum Thema Umwelt');
      expect(badges['Mobilität/Verkehr']!.name, 'Bimmelbahn');
      expect(badges['Sicherheit']!.tier, 0);
    });

    test('tiers follow the thresholds', () {
      TopicBadge badge(int actions) =>
          TopicBadge(tag: 'Umwelt/Natur', actions: actions);
      expect(badge(2).name, isNull);
      expect(badge(2).nextAt, 3);
      expect(badge(10).name, 'Komposthaufen');
      expect(badge(25).name, 'Mammutbaum');
      expect(badge(25).nextAt, isNull);
    });

    test('every topic has a name for every tier', () {
      final log = ActionLog([_done(_now)]);
      for (final badge in Progress.of(log, _now).badges) {
        expect(kBadgeNames[badge.tag], hasLength(kBadgeTiers.length));
      }
    });

    test('stickers come in the order they were earned', () {
      final log = ActionLog([
        _done(_now, ['Familie/Kinder']),
        _done(_now, ['Familie/Kinder']),
        _done(_now, ['Familie/Kinder']),
      ]);
      final earned = Progress.of(log, _now).earned;
      expect(
        [for (final s in earned) s.title],
        ['Kazoo', 'Trillerpfeife', 'Schnuller'],
      );
      expect(earned.last.asset, 'assets/badges/familie-1.svg');
      expect(earned.last.tier, 1);
      expect(earned.first.asset, 'assets/badges/alle-1.svg');
    });

    test('every sticker file the app asks for exists', () {
      final assets = {
        for (final m in kMilestones) m.asset,
        for (final tag in kTopicTags)
          for (var tier = 1; tier <= kBadgeTiers.length; tier++)
            'assets/badges/${topicSlug(tag)}-$tier.svg',
      };
      for (final asset in assets) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    });

    test('the track over all topics', () {
      final progress = Progress.of(
        ActionLog([for (var i = 0; i < 4; i++) _done(_now)]),
        _now,
      );
      expect(progress.milestone!.title, 'Trillerpfeife');
      expect(progress.nextMilestone!.count, 5);
      expect(Progress.of(const ActionLog(), _now).milestone, isNull);
    });
  });

  group('moment', () {
    ProgressMoment? after(List<ActionLogEntry> before, ActionLogEntry next) =>
        ProgressMoment.between(
          Progress.of(ActionLog(before), _now),
          Progress.of(ActionLog([...before, next]), _now),
        );

    test('the first action earns the first badge', () {
      expect(after([], _done(_now))!.milestone!.title, 'Kazoo');
    });

    test('nothing between badges', () {
      final before = [_done(_now), _done(_now), _done(_now)];
      expect(after(before, _done(_now)), isNull);
    });

    test('both tracks at once', () {
      final before = [
        _done(_now, ['Familie/Kinder']),
        _done(_now, ['Familie/Kinder']),
        _done(_now),
        _done(_now),
      ];
      final moment = after(before, _done(_now, ['Familie/Kinder']))!;
      expect(moment.milestone!.title, 'Tröte');
      expect(moment.badges.single.name, 'Schnuller');
    });

    test('carrying the streak on is no badge', () {
      final before = [_done(_weeksAgo(2)), _done(_weeksAgo(1))];
      expect(after([...before, _done(_weeksAgo(1))], _done(_now)), isNull);
    });
  });
}
