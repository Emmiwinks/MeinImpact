// Calibration harness for the interest learning: replays synthetic users day
// by day against the real ranker and measures what the config produces.
// There is no behaviour data to tune on (nothing leaves the device), so this
// is how a config change is judged: edit a number in InterestConfig, run
//   flutter test test/interest_calibration_test.dart
// and read the printed metrics. The assertions are deliberately loose
// guard rails; the printed numbers are the real output.
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/interest_config.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

const _topics = [
  'Mobilität/Verkehr',
  'Umwelt/Natur',
  'Wohnen/Miete',
  'Gesundheit/Pflege',
  'Bildung/Ausbildung',
];

// 8 cards per topic. Every topic is equally appealing, except that the
// persona's favourite is made slightly LESS appealing, so interest has to
// overcome a real baseline instead of winning on ties.
List<Opportunity> _pool({required String favourite}) {
  return [
    for (final topic in _topics)
      for (var i = 0; i < 8; i++)
        Opportunity(
          id: '$topic-$i',
          sourceOrg: 'openPetition',
          sourceUrl: 'https://example.org/$topic-$i',
          kind: OpportunityKind.petition,
          isAnnounced: false,
          region: 'bund',
          title: '$topic $i',
          summary: '',
          affectedTags: [topic],
          werteRelevanz: const {},
          proArgumente: const [],
          contraArgumente: const [],
          personalImpactSnippets: const {},
          firstSeenAt: DateTime(2026, 11, 1),
          everydayRelevance: 3,
          accessibility: topic == favourite ? 3 : 4,
        ),
  ];
}

class _Result {
  _Result(
    this.dayFavouriteLeads,
    this.favouriteShareOfTop10,
    this.topicsInTop10,
  );
  // First day the favourite topic holds slot 1 (null = never).
  final int? dayFavouriteLeads;
  final double favouriteShareOfTop10;
  final int topicsInTop10;

  @override
  String toString() =>
      'leads from day $dayFavouriteLeads, favourite share of top 10: '
      '${(favouriteShareOfTop10 * 100).round()}%, topics in top 10: '
      '$topicsInTop10';
}

/// A user who each day scans the feed and opens up to [opensPerDay] cards of
/// their [favourite] topic among the first [scanDepth] slots, and acts on
/// one every [actEvery] days.
UserProfile _live({
  required InterestConfig config,
  required String favourite,
  required UserProfile start,
  required DateTime from,
  required int days,
  int opensPerDay = 2,
  int scanDepth = 40,
  int actEvery = 3,
  void Function(int day, List<RankedOpportunity> feed)? onDay,
}) {
  final ranker = OpportunityRelevanceRanker(interestConfig: config);
  var profile = start;
  for (var day = 0; day < days; day++) {
    final now = from.add(Duration(days: day));
    final feed = ranker.rank(_pool(favourite: favourite), profile, now: now);
    onDay?.call(day, feed);
    var opened = 0;
    for (final ranked in feed.take(scanDepth)) {
      if (opened >= opensPerDay) break;
      if (ranked.opportunity.affectedTags.first != favourite) continue;
      opened++;
      var interests = profile.interests.record(
        ranked.opportunity.affectedTags,
        InterestSignal.opened,
        now,
        config,
      );
      if (day % actEvery == 0 && opened == 1) {
        interests = interests.record(
          ranked.opportunity.affectedTags,
          InterestSignal.acted,
          now,
          config,
        );
      }
      profile = profile.copyWith(interests: interests);
    }
  }
  return profile;
}

_Result _measure(InterestConfig config, {int days = 30}) {
  const favourite = 'Umwelt/Natur';
  int? leads;
  List<RankedOpportunity> last = const [];
  _live(
    config: config,
    favourite: favourite,
    start: const UserProfile(),
    from: DateTime(2026, 11, 1),
    days: days,
    onDay: (day, feed) {
      last = feed;
      if (leads == null &&
          feed.first.opportunity.affectedTags.first == favourite) {
        leads = day;
      }
    },
  );
  final top10 = last.take(10).toList();
  return _Result(
    leads,
    top10.where((r) => r.opportunity.affectedTags.first == favourite).length /
        10,
    top10.map((r) => r.opportunity.affectedTags.first).toSet().length,
  );
}

void main() {
  test('default config: a consistent user gets their topic on top soon', () {
    final result = _measure(const InterestConfig());
    // ignore: avoid_print
    print('default: $result');

    expect(result.dayFavouriteLeads, isNotNull);
    expect(result.dayFavouriteLeads, lessThan(10));
  });

  test('default config: the feed never collapses into one topic', () {
    final result = _measure(const InterestConfig());

    expect(result.favouriteShareOfTop10, lessThanOrEqualTo(0.8));
    expect(result.topicsInTop10, greaterThanOrEqualTo(3));
  });

  test('a changed config visibly changes the outcome (tuning works)', () {
    final slow =
        _measure(const InterestConfig(openedDelta: 0.03, actedDelta: 0.1));
    final fast =
        _measure(const InterestConfig(openedDelta: 0.3, actedDelta: 0.6));
    // ignore: avoid_print
    print('slow: $slow\nfast: $fast');

    expect(
      fast.dayFavouriteLeads ?? 999,
      lessThan(slow.dayFavouriteLeads ?? 999),
    );
  });

  test('exploration off lets the favourite take over more of the feed', () {
    final withExploration = _measure(const InterestConfig());
    final without = _measure(const InterestConfig(explorationInterval: 0));
    // ignore: avoid_print
    print('with exploration: $withExploration\nwithout: $without');

    expect(
      without.favouriteShareOfTop10,
      greaterThanOrEqualTo(withExploration.favouriteShareOfTop10),
    );
  });

  test('a user who changes taste is followed within a few weeks', () {
    const config = InterestConfig();
    final from = DateTime(2026, 11, 1);
    final first = _live(
      config: config,
      favourite: 'Umwelt/Natur',
      start: const UserProfile(),
      from: from,
      days: 30,
    );

    int? newLeads;
    _live(
      config: config,
      favourite: 'Mobilität/Verkehr',
      start: first,
      from: from.add(const Duration(days: 30)),
      days: 30,
      onDay: (day, feed) {
        if (newLeads == null &&
            feed.first.opportunity.affectedTags.first == 'Mobilität/Verkehr') {
          newLeads = day;
        }
      },
    );
    // ignore: avoid_print
    print('taste change: new favourite leads after $newLeads days');

    expect(newLeads, isNotNull);
    expect(newLeads, lessThan(16));
  });

  test('half-life sweep: how fast a taste change is followed', () {
    for (final days in [7, 14, 30]) {
      final config = InterestConfig(halfLife: Duration(days: days));
      final from = DateTime(2026, 11, 1);
      final first = _live(
        config: config,
        favourite: 'Umwelt/Natur',
        start: const UserProfile(),
        from: from,
        days: 30,
      );
      int? newLeads;
      _live(
        config: config,
        favourite: 'Mobilität/Verkehr',
        start: first,
        from: from.add(const Duration(days: 30)),
        days: 40,
        onDay: (day, feed) {
          if (newLeads == null &&
              feed.first.opportunity.affectedTags.first ==
                  'Mobilität/Verkehr') {
            newLeads = day;
          }
        },
      );
      // ignore: avoid_print
      print('half-life $days d: new favourite leads after $newLeads days');
    }
  });

  test('a user who stops using the app fades back to the neutral feed', () {
    const config = InterestConfig();
    final from = DateTime(2026, 11, 1);
    final profile = _live(
      config: config,
      favourite: 'Umwelt/Natur',
      start: const UserProfile(),
      from: from,
      days: 30,
    );

    final back = from.add(const Duration(days: 30 + 180));

    expect(profile.interests.hasSignal(back, config), isFalse);
  });
}
