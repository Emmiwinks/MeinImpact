import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/interest_config.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

final _now = DateTime(2026, 11, 3);
const _config = InterestConfig();

Opportunity _opportunity(String id, List<String> tags, {int score = 3}) {
  return Opportunity(
    id: id,
    sourceOrg: 'openPetition',
    sourceUrl: 'https://example.org/$id',
    kind: OpportunityKind.petition,
    isAnnounced: false,
    region: 'bund',
    title: 'Title $id',
    summary: 'Summary $id',
    affectedTags: tags,
    werteRelevanz: const {},
    proArgumente: const [],
    contraArgumente: const [],
    personalImpactSnippets: const {},
    firstSeenAt: DateTime(2026, 11, 1),
    everydayRelevance: score,
    accessibility: score,
  );
}

InterestWeights _record(
  InterestWeights weights,
  List<String> tags,
  InterestSignal signal, {
  DateTime? at,
  InterestConfig config = _config,
}) =>
    weights.record(tags, signal, at ?? _now, config);

InterestWeights _liking(String tag, {int times = 3}) {
  var weights = const InterestWeights();
  for (var i = 0; i < times; i++) {
    weights = _record(weights, [tag], InterestSignal.acted);
  }
  return weights;
}

double _weight(InterestWeights w, String tag, {DateTime? at}) =>
    w.weightOf(tag, at ?? _now, _config);

void main() {
  group('InterestWeights', () {
    test('behaviour raises the weight of the opportunity\'s tags', () {
      final weights = _record(
        const InterestWeights(),
        ['Mobilität/Verkehr'],
        InterestSignal.opened,
      );

      expect(_weight(weights, 'Mobilität/Verkehr'), closeTo(0.1, 1e-9));
      expect(_weight(weights, 'Wohnen/Miete'), 0);
    });

    test('a completed action counts more than opening', () {
      final opened = _record(
        const InterestWeights(),
        ['Umwelt/Natur'],
        InterestSignal.opened,
      );
      final acted = _record(
        const InterestWeights(),
        ['Umwelt/Natur'],
        InterestSignal.acted,
      );

      expect(
        _weight(acted, 'Umwelt/Natur'),
        greaterThan(_weight(opened, 'Umwelt/Natur')),
      );
    });

    test('many tags share the signal instead of inflating each', () {
      final weights = _record(
        const InterestWeights(),
        [
          'Wohnen/Miete',
          'Mobilität/Verkehr',
          'Umwelt/Natur',
          'Arbeit/Einkommen',
        ],
        InterestSignal.acted,
      );

      expect(_weight(weights, 'Wohnen/Miete'), closeTo(0.15, 1e-9));
    });

    test('duplicate tags and empty tag lists are harmless', () {
      final doubled = _record(
        const InterestWeights(),
        ['Umwelt/Natur', 'Umwelt/Natur'],
        InterestSignal.opened,
      );

      expect(_weight(doubled, 'Umwelt/Natur'), closeTo(0.1, 1e-9));
      expect(
        _record(const InterestWeights(), [], InterestSignal.acted).weights,
        isEmpty,
      );
    });

    test('weights are capped at the configured maximum', () {
      expect(_weight(_liking('Umwelt/Natur', times: 50), 'Umwelt/Natur'), 1.0);

      const capped = InterestConfig(maxWeight: 0.5);
      var weights = const InterestWeights();
      for (var i = 0; i < 10; i++) {
        weights = _record(
          weights,
          ['Umwelt/Natur'],
          InterestSignal.acted,
          config: capped,
        );
      }

      expect(weights.weightOf('Umwelt/Natur', _now, capped), 0.5);
    });

    test('weights halve after the half-life and never flip sign', () {
      final weights = _liking('Umwelt/Natur');
      final fresh = _weight(weights, 'Umwelt/Natur');

      expect(
        _weight(weights, 'Umwelt/Natur', at: _now.add(_config.halfLife)),
        closeTo(fresh / 2, 1e-9),
      );
      expect(
        _weight(
          weights,
          'Umwelt/Natur',
          at: _now.add(const Duration(days: 900)),
        ),
        greaterThan(0),
      );
    });

    test('a clock set back does not amplify weights', () {
      final weights = _liking('Umwelt/Natur');

      expect(
        _weight(
          weights,
          'Umwelt/Natur',
          at: _now.subtract(const Duration(days: 5)),
        ),
        _weight(weights, 'Umwelt/Natur'),
      );
    });

    test('recording decays the older weights before adding', () {
      final old = _liking('Umwelt/Natur');
      final later = _now.add(_config.halfLife);

      final updated =
          _record(old, ['Wohnen/Miete'], InterestSignal.opened, at: later);

      expect(
        _weight(updated, 'Umwelt/Natur', at: later),
        closeTo(_weight(old, 'Umwelt/Natur') / 2, 1e-9),
      );
      expect(updated.asOf, later);
    });

    test('survives a JSON round trip, and an empty profile loads', () {
      final restored =
          InterestWeights.fromJson(_liking('Umwelt/Natur').toJson());

      expect(
        _weight(restored, 'Umwelt/Natur'),
        _weight(_liking('Umwelt/Natur'), 'Umwelt/Natur'),
      );
      expect(const InterestWeights().hasSignal(_now, _config), isFalse);
      expect(UserProfile.fromJson(const {}).interests.weights, isEmpty);
    });

    test('names a reason only for a clearly liked tag', () {
      final weak = _record(
        const InterestWeights(),
        ['Umwelt/Natur'],
        InterestSignal.opened,
      );

      expect(weak.reasonTag(['Umwelt/Natur'], _now, _config), isNull);
      expect(
        _liking('Umwelt/Natur')
            .reasonTag(['Wohnen/Miete', 'Umwelt/Natur'], _now, _config),
        'Umwelt/Natur',
      );
    });

    test('profile edits keep the learned interests', () {
      final profile = UserProfile(interests: _liking('Umwelt/Natur'));

      final edited = profile.copyWith(werte: const {'wirtschaft_staat': 1});

      expect(_weight(edited.interests, 'Umwelt/Natur'), greaterThan(0));
    });
  });

  group('InterestConfig', () {
    test('signal sizes and half-life come from the config', () {
      const eager = InterestConfig(
        openedDelta: 0.5,
        halfLife: Duration(days: 1),
      );
      final weights = _record(
        const InterestWeights(),
        ['Umwelt/Natur'],
        InterestSignal.opened,
        config: eager,
      );

      expect(weights.weightOf('Umwelt/Natur', _now, eager), 0.5);
      expect(
        weights.weightOf(
          'Umwelt/Natur',
          _now.add(const Duration(days: 1)),
          eager,
        ),
        closeTo(0.25, 1e-9),
      );
    });

    test('exploration interval follows the config, 0 turns it off', () {
      final profile = UserProfile(interests: _liking('Umwelt/Natur'));
      final pool = [
        for (var i = 0; i < 6; i++) _opportunity('liked$i', ['Umwelt/Natur']),
        _opportunity('fresh', ['Migration/Integration'], score: 1),
      ];

      final off = const OpportunityRelevanceRanker(
        interestConfig: InterestConfig(explorationInterval: 0),
      ).rank(pool, profile, now: _now);
      final every3 = const OpportunityRelevanceRanker(
        interestConfig: InterestConfig(explorationInterval: 3),
      ).rank(pool, profile, now: _now);

      expect(off.last.opportunity.id, 'fresh');
      expect(every3[2].opportunity.id, 'fresh');
    });
  });

  group('ranking with interests', () {
    const ranker = OpportunityRelevanceRanker();

    test('a liked topic outranks an equally appealing one', () {
      final profile = UserProfile(interests: _liking('Umwelt/Natur'));
      final pool = [
        _opportunity('other', ['Wohnen/Miete']),
        _opportunity('liked', ['Umwelt/Natur']),
      ];

      final ranked = ranker.rank(pool, profile, now: _now);

      expect(ranked.first.opportunity.id, 'liked');
      expect(ranked.first.interestTag, 'Umwelt/Natur');
      expect(ranked.last.interestTag, isNull);
    });

    test('interest nudges but cannot bury a far more appealing card', () {
      final profile =
          UserProfile(interests: _liking('Umwelt/Natur', times: 50));
      final pool = [
        _opportunity('niche-liked', ['Umwelt/Natur'], score: 1),
        _opportunity('everyday', ['Wohnen/Miete'], score: 5),
      ];

      final ranked = ranker.rank(pool, profile, now: _now);

      expect(ranked.first.opportunity.id, 'everyday');
    });

    test('never drops cards, even with strong interests', () {
      final profile =
          UserProfile(interests: _liking('Umwelt/Natur', times: 50));
      final pool = [
        for (var i = 0; i < 12; i++) _opportunity('o$i', ['Wohnen/Miete']),
        _opportunity('liked', ['Umwelt/Natur']),
      ];

      expect(ranker.rank(pool, profile, now: _now), hasLength(13));
    });

    test('every fifth slot explores a topic without an opinion', () {
      final profile = UserProfile(interests: _liking('Umwelt/Natur'));
      final pool = [
        for (var i = 0; i < 6; i++) _opportunity('liked$i', ['Umwelt/Natur']),
        _opportunity('fresh', ['Migration/Integration'], score: 1),
      ];

      final ranked = ranker.rank(pool, profile, now: _now);

      expect(ranked[4].opportunity.id, 'fresh');
    });

    test('without interests the order is untouched by exploration', () {
      final pool = [
        for (var i = 0; i < 6; i++) _opportunity('a$i', ['Umwelt/Natur']),
        _opportunity('last', ['Migration/Integration'], score: 1),
      ];

      final ranked = ranker.rank(pool, const UserProfile(), now: _now);

      expect(ranked.last.opportunity.id, 'last');
    });

    test('exploration with nothing unexplored keeps all cards', () {
      final profile = UserProfile(interests: _liking('Umwelt/Natur'));
      final pool = [
        for (var i = 0; i < 6; i++) _opportunity('liked$i', ['Umwelt/Natur']),
      ];

      expect(ranker.rank(pool, profile, now: _now), hasLength(6));
    });
  });
}
