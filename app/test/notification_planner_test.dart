import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/notifications/domain/notification_planner.dart';
import 'package:meinimpact/src/features/notifications/domain/notification_state.dart';
import 'package:meinimpact/src/features/notifications/domain/notification_texts.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';

// A Monday, and that week's Friday morning.
final _monday = DateTime(2026, 11, 16);
final _friday = DateTime(2026, 11, 20, 10);

const _profile = UserProfile(lebenslagen: {'mieter'});

void main() {
  test('the dates used here fall on the right weekdays', () {
    expect(_monday.weekday, DateTime.monday);
    expect(_friday.weekday, DateTime.friday);
  });

  group('flame', () {
    // Last action two weeks back: this week only pauses the streak, and it
    // ends at midnight on Sunday.
    final paused = _log([_entry('a', doneAt: DateTime(2026, 11, 4))]);

    test('warns on Sunday evening when the flame would go out', () {
      final plan = _plan(log: paused);

      final flame = plan.schedule.single;
      expect(flame.kind, NotificationKind.flame);
      expect(flame.key, 'flame:2026-11-16');
      expect(flame.at, DateTime(2026, 11, 22, 17));
    });

    test('says nothing while the streak burns', () {
      final plan = _plan(log: _log([_entry('a', doneAt: _monday)]));

      expect(plan.schedule, isEmpty);
    });

    test('says nothing when switched off in Android', () {
      final plan = _plan(log: paused, off: {NotificationChannel.flame});

      expect(plan.schedule, isEmpty);
    });

    test('comes right away when Sunday 17:00 has passed, not after 21:00', () {
      final late = _plan(log: paused, now: DateTime(2026, 11, 22, 18));
      final night = _plan(log: paused, now: DateTime(2026, 11, 22, 21, 30));

      expect(late.show.single.kind, NotificationKind.flame);
      expect(night.show, isEmpty);
      expect(night.schedule, isEmpty);
    });
  });

  group('council vote', () {
    ActionLogEntry vote({List<String>? lebenslagen = const ['mieter']}) =>
        _entry(
          'vote',
          kind: OpportunityKind.decision,
          title: 'Soll Dresden mehr Radwege bauen?',
          doneAt: DateTime(2026, 11, 18),
          closesOn: DateTime(2026, 11, 25),
          lebenslagen: lebenslagen,
        );

    test('comes the evening before, naming the vote', () {
      final plan = _plan(log: _log([vote()]));

      final notification = plan.schedule.single;
      expect(notification.at, DateTime(2026, 11, 24, 18));
      expect(notification.body, contains('Soll Dresden mehr Radwege bauen?'));
      expect(notification.opportunityId, 'vote');
    });

    test('never names an action about a private Lebenslage', () {
      final plan = _plan(
        log: _log([
          vote(lebenslagen: const ['chronisch_krank']),
        ]),
      );

      final notification = plan.schedule.single;
      expect(notification.title, isNot(contains('Radwege')));
      expect(notification.body, isNot(contains('Radwege')));
    });

    test('treats an action saved without its Lebenslagen as private', () {
      final plan = _plan(log: _log([vote(lebenslagen: null)]));

      expect(plan.schedule.single.body, isNot(contains('Radwege')));
    });
  });

  group('news on starred actions', () {
    final log = _log([_entry('a', title: 'Skatehalle Pieschen')]);
    ImpactNewsFeed feed(List<String> urls) => ImpactNewsFeed({
          'a': ImpactNewsEntry(
            checkedAt: _friday,
            items: [
              for (final url in urls)
                ImpactNewsItem(
                  level: 'exact',
                  kind: 'news',
                  title: 'Bericht $url',
                  url: url,
                  snippet: '',
                ),
            ],
          ),
        });

    test('what is there when starring counts as known', () {
      final plan = _plan(log: log, starred: {'a'}, news: feed(['u1']));

      expect(plan.show, isEmpty);
      expect(plan.state.newsSeen['a'], {'u1'});
    });

    test('a new report comes right away and is then known', () {
      const known = NotificationState(
        newsSeen: {
          'a': {'u1'},
        },
      );

      final plan = _plan(
        log: log,
        starred: {'a'},
        news: feed(['u1', 'u2']),
        state: known,
      );

      final notification = plan.show.single;
      expect(notification.title, 'Neues zu: Skatehalle Pieschen');
      expect(notification.body, 'Bericht u2');
      expect(plan.state.newsSeen['a'], {'u1', 'u2'});
    });

    test('waits through the night', () {
      final plan = _plan(
        log: log,
        starred: {'a'},
        news: feed(['u1', 'u2']),
        state: const NotificationState(
          newsSeen: {
            'a': {'u1'},
          },
        ),
        now: DateTime(2026, 11, 20, 23),
      );

      expect(plan.show, isEmpty);
      expect(plan.state.newsSeen['a'], {'u1'});
    });

    test('background reports never notify', () {
      final plan = _plan(
        log: log,
        starred: {'a'},
        news: ImpactNewsFeed({
          'a': ImpactNewsEntry(
            checkedAt: _friday,
            items: const [
              ImpactNewsItem(
                level: 'background',
                kind: 'news',
                title: 'Hintergrund',
                url: 'u2',
                snippet: '',
              ),
            ],
          ),
        }),
        state: const NotificationState(newsSeen: {'a': {}}),
      );

      expect(plan.show, isEmpty);
    });
  });

  test('a petition reaching its goal after signing is celebrated', () {
    final plan = _plan(
      log: _log([
        _entry('p', supportCount: 50, supportGoal: 100, title: 'Kita retten'),
      ]),
      pool: [_opportunity('p', supportCount: 120, supportGoal: 100)],
    );

    final result = plan.show.single;
    expect(result.kind, NotificationKind.result);
    expect(result.body, contains('Kita retten'));
  });

  group('Monday', () {
    final pool = [
      _opportunity(
        'new',
        title: 'Mietspiegel mitgestalten',
        lebenslagen: const ['mieter'],
        firstSeenAt: DateTime(2026, 11, 18),
      ),
      _opportunity('old', lebenslagen: const ['mieter']),
    ];

    test('counts new opportunities that fit, at 9:00', () {
      final plan = _plan(pool: pool);

      final week = plan.schedule.single;
      expect(week.kind, NotificationKind.week);
      expect(week.at, DateTime(2026, 11, 23, kWeekHour));
      expect(
        kWeekTitles.map((t) => t.replaceAll('{x}', '1')),
        contains(week.title),
      );
    });

    test('is skipped when the app was already open that Monday', () {
      final plan = _plan(
        // New in the week before the following Monday.
        pool: [
          _opportunity(
            'newer',
            lebenslagen: const ['mieter'],
            firstSeenAt: DateTime(2026, 11, 23, 6),
          ),
        ],
        now: DateTime(2026, 11, 23, 7),
        state: NotificationState(lastOpenedAt: DateTime(2026, 11, 23, 7)),
      );

      expect(plan.schedule.single.at, DateTime(2026, 11, 30, kWeekHour));
    });

    test('comes back when its channel is switched on again', () {
      final first = _plan(pool: pool);
      final switchedOff = _plan(
        state: first.state,
        off: {NotificationChannel.week},
      );
      final switchedOn = _plan(state: switchedOff.state);

      expect(switchedOff.schedule, isEmpty);
      expect(switchedOn.schedule.single.key, first.schedule.single.key);
    });

    test('stays as planned when the pool was not loaded', () {
      final first = _plan(pool: pool);
      final second = _plan(state: first.state);

      expect(second.schedule.single.key, first.schedule.single.key);
      expect(second.cancel, isEmpty);
    });
  });

  group('limits', () {
    test('one a day: the more important one wins', () {
      // The vote is on Monday, so its evening-before falls on the Sunday
      // the flame would go out.
      final plan = _plan(
        log: _log([
          _entry('a', doneAt: DateTime(2026, 11, 4)),
          _entry(
            'vote',
            kind: OpportunityKind.decision,
            doneAt: DateTime(2026, 11, 4),
            closesOn: DateTime(2026, 11, 23),
          ),
        ]),
      );

      expect(plan.schedule.single.kind, NotificationKind.decision);
    });

    test('a channel switched off in Android leaves the day to another', () {
      final plan = _plan(
        log: _log([
          _entry('a', doneAt: DateTime(2026, 11, 4)),
          _entry(
            'vote',
            kind: OpportunityKind.decision,
            doneAt: DateTime(2026, 11, 4),
            closesOn: DateTime(2026, 11, 23),
          ),
        ]),
        off: {NotificationChannel.news},
      );

      expect(plan.schedule.single.kind, NotificationKind.flame);
    });

    test('a key is never shown twice', () {
      final paused = _log([_entry('a', doneAt: DateTime(2026, 11, 4))]);
      final plan = _plan(
        log: paused,
        state: NotificationState(
          shown: {'flame:2026-11-16': DateTime(2026, 11, 19)},
        ),
      );

      expect(plan.schedule, isEmpty);
    });

    test('scheduled ones that came due count as shown', () {
      final due = PlannedNotification(
        key: 'week:2026-11-16',
        kind: NotificationKind.week,
        at: DateTime(2026, 11, 20, 9),
        title: 't',
        body: 'b',
      );

      final plan = _plan(state: NotificationState(planned: [due]));

      expect(plan.state.shown, contains('week:2026-11-16'));
      expect(plan.cancel, isEmpty);
    });

    test('what is no longer wanted is cancelled', () {
      final stale = PlannedNotification(
        key: 'flame:2026-11-16',
        kind: NotificationKind.flame,
        at: DateTime(2026, 11, 22, 17),
        title: 't',
        body: 'b',
      );

      // The user acted this week: the flame is safe.
      final plan = _plan(
        log: _log([_entry('a', doneAt: _monday)]),
        state: NotificationState(planned: [stale]),
      );

      expect(plan.cancel, [stale.id]);
    });
  });

  group('cards looked at', () {
    final leftSite = NotificationState(
      lookedAt: {
        'c': LookedAtCard(
          card: _entry('c', title: 'Lärmaktionsplan'),
          at: DateTime(2026, 11, 20, 9),
          openedSite: true,
        ),
      },
    );

    test('"Abgeschickt?" is off for the beta', () {
      expect(_plan(state: leftSite).schedule, isEmpty);
    });

    test('asks the evening after leaving the site without Fertig', () {
      final plan = _plan(state: leftSite, askIfTookPart: true);

      final ask = plan.schedule.single;
      expect(ask.kind, NotificationKind.tookPart);
      expect(ask.at, DateTime(2026, 11, 21, kTookPartHour));
      expect(ask.body, contains('Lärmaktionsplan'));
    });

    test('reminds two days before a card closes', () {
      final plan = _plan(
        state: NotificationState(
          lookedAt: {
            'c': LookedAtCard(
              card: _entry('c', closesOn: DateTime(2026, 11, 26)),
              at: DateTime(2026, 11, 19),
            ),
          },
        ),
      );

      expect(plan.schedule.single.at, DateTime(2026, 11, 24, kDeadlineHour));
    });

    test('forgets a card once it is done', () {
      final plan = _plan(
        log: _log([_entry('c', doneAt: DateTime(2026, 11, 19))]),
        state: NotificationState(
          lookedAt: {
            'c': LookedAtCard(
              card: _entry('c'),
              at: DateTime(2026, 11, 18),
              openedSite: true,
            ),
          },
        ),
      );

      expect(plan.state.lookedAt, isEmpty);
    });
  });

  test('the state round-trips through JSON', () {
    final plan = _plan(
      log: _log([_entry('a', doneAt: DateTime(2026, 11, 4))]),
      state: NotificationState(
        lastOpenedAt: _friday,
        lookedAt: {'c': LookedAtCard(card: _entry('c'), at: _friday)},
      ),
    );

    final restored = NotificationState.fromJson(plan.state.toJson());

    expect(restored.lastOpenedAt, _friday);
    expect(restored.planned.single.key, plan.schedule.single.key);
    expect(restored.planned.single.at, plan.schedule.single.at);
    expect(restored.lookedAt['c']!.card.opportunityId, 'c');
  });

  test('texts with a count need at least two', () {
    for (var week = 0; week < kWeekTitles.length; week++) {
      expect(weekText(week, 1, null).title, isNot(contains('1')));
    }
    for (var week = 0; week < kFlameTexts.length; week++) {
      expect(flameText(week, 1).title, isNot(contains('1')));
    }
  });
}

NotificationPlan _plan({
  ActionLog log = const ActionLog(),
  Set<String> starred = const {},
  NotificationState state = const NotificationState(),
  Set<NotificationChannel> off = const {},
  List<Opportunity>? pool,
  ImpactNewsFeed? news,
  DateTime? now,
  bool askIfTookPart = false,
}) =>
    planNotifications(
      now: now ?? _friday,
      state: state,
      log: log,
      starred: starred,
      profile: _profile,
      off: off,
      pool: pool,
      news: news,
      askIfTookPart: askIfTookPart,
    );

ActionLog _log(List<ActionLogEntry> entries) => ActionLog(entries);

ActionLogEntry _entry(
  String id, {
  DateTime? doneAt,
  OpportunityKind kind = OpportunityKind.petition,
  String title = 'Eine Aktion',
  DateTime? closesOn,
  List<String>? lebenslagen = const ['mieter'],
  int? supportCount,
  int? supportGoal,
}) =>
    ActionLogEntry(
      opportunityId: id,
      doneAt: doneAt ?? DateTime(2026, 11, 4),
      via: ActionVia.inAppBrowser,
      title: title,
      kind: kind,
      sourceOrg: 'WeAct',
      sourceUrl: 'https://example.org/$id',
      closesOn: closesOn,
      lebenslagen: lebenslagen,
      supportCount: supportCount,
      supportGoal: supportGoal,
    );

Opportunity _opportunity(
  String id, {
  String title = 'Eine Gelegenheit',
  List<String> lebenslagen = const [],
  DateTime? firstSeenAt,
  int? supportCount,
  int? supportGoal,
}) =>
    Opportunity(
      id: id,
      sourceOrg: 'WeAct',
      sourceUrl: 'https://example.org/$id',
      kind: OpportunityKind.petition,
      isAnnounced: false,
      region: 'dresden',
      title: title,
      summary: '',
      affectedTags: const [],
      werteRelevanz: const {},
      proArgumente: const [],
      contraArgumente: const [],
      personalImpactSnippets: const {},
      firstSeenAt: firstSeenAt ?? DateTime(2026, 10, 1),
      lebenslagen: lebenslagen,
      supportCount: supportCount,
      supportGoal: supportGoal,
    );
