import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

final _now = DateTime(2026, 11, 3);

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

InterestWeights _liking(String tag, {int times = 3}) {
  var weights = const InterestWeights();
  for (var i = 0; i < times; i++) {
    weights = weights.record([tag], InterestSignal.acted, _now);
  }
  return weights;
}

void main() {
  group('InterestWeights', () {
    test('behaviour raises the weight of the opportunity\'s tags', () {
      final weights = const InterestWeights()
          .record(['Mobilität/Verkehr'], InterestSignal.opened, _now);

      expect(weights.weightOf('Mobilität/Verkehr', _now), closeTo(0.1, 1e-9));
      expect(weights.weightOf('Wohnen/Miete', _now), 0);
    });

    test('a completed action counts more than opening', () {
      final opened = const InterestWeights()
          .record(['Umwelt/Natur'], InterestSignal.opened, _now);
      final acted = const InterestWeights()
          .record(['Umwelt/Natur'], InterestSignal.acted, _now);

      expect(
        acted.weightOf('Umwelt/Natur', _now),
        greaterThan(opened.weightOf('Umwelt/Natur', _now)),
      );
    });

    test('many tags share the signal instead of inflating each', () {
      final weights = const InterestWeights().record(
        [
          'Wohnen/Miete',
          'Mobilität/Verkehr',
          'Umwelt/Natur',
          'Arbeit/Einkommen',
        ],
        InterestSignal.acted,
        _now,
      );

      expect(weights.weightOf('Wohnen/Miete', _now), closeTo(0.15, 1e-9));
    });

    test('duplicate tags and empty tag lists are harmless', () {
      final doubled = const InterestWeights().record(
        ['Umwelt/Natur', 'Umwelt/Natur'],
        InterestSignal.opened,
        _now,
      );

      expect(doubled.weightOf('Umwelt/Natur', _now), closeTo(0.1, 1e-9));
      expect(
        const InterestWeights().record([], InterestSignal.acted, _now).weights,
        isEmpty,
      );
    });

    test('weights are capped at +1', () {
      final weights = _liking('Umwelt/Natur', times: 50);

      expect(weights.weightOf('Umwelt/Natur', _now), 1.0);
    });

    test('weights halve after the half-life and never flip sign', () {
      final weights = _liking('Umwelt/Natur');
      final fresh = weights.weightOf('Umwelt/Natur', _now);

      final later = _now.add(InterestWeights.halfLife);
      expect(
        weights.weightOf('Umwelt/Natur', later),
        closeTo(fresh / 2, 1e-9),
      );
      expect(
        weights.weightOf('Umwelt/Natur', _now.add(const Duration(days: 900))),
        greaterThan(0),
      );
    });

    test('a clock set back does not amplify weights', () {
      final weights = _liking('Umwelt/Natur');

      expect(
        weights.weightOf(
          'Umwelt/Natur',
          _now.subtract(const Duration(days: 5)),
        ),
        weights.weightOf('Umwelt/Natur', _now),
      );
    });

    test('recording decays the older weights before adding', () {
      final old = _liking('Umwelt/Natur');
      final later = _now.add(InterestWeights.halfLife);

      final updated =
          old.record(['Wohnen/Miete'], InterestSignal.opened, later);

      expect(
        updated.weightOf('Umwelt/Natur', later),
        closeTo(old.weightOf('Umwelt/Natur', _now) / 2, 1e-9),
      );
      expect(updated.asOf, later);
    });

    test('survives a JSON round trip, and an empty profile loads', () {
      final restored =
          InterestWeights.fromJson(_liking('Umwelt/Natur').toJson());

      expect(
        restored.weightOf('Umwelt/Natur', _now),
        _liking('Umwelt/Natur').weightOf('Umwelt/Natur', _now),
      );
      expect(const InterestWeights().hasSignal(_now), isFalse);
      expect(UserProfile.fromJson(const {}).interests.weights, isEmpty);
    });

    test('names a reason only for a clearly liked tag', () {
      final weak = const InterestWeights()
          .record(['Umwelt/Natur'], InterestSignal.opened, _now);

      expect(weak.reasonTag(['Umwelt/Natur'], _now), isNull);
      expect(
        _liking('Umwelt/Natur')
            .reasonTag(['Wohnen/Miete', 'Umwelt/Natur'], _now),
        'Umwelt/Natur',
      );
    });

    test('profile edits keep the learned interests', () {
      final profile = UserProfile(interests: _liking('Umwelt/Natur'));

      final edited = profile.copyWith(werte: const {'wirtschaft_staat': 1});

      expect(edited.interests.weightOf('Umwelt/Natur', _now), greaterThan(0));
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

    test('exploration with nothing unexplored keeps the order', () {
      final profile = UserProfile(interests: _liking('Umwelt/Natur'));
      final pool = [
        for (var i = 0; i < 6; i++) _opportunity('liked$i', ['Umwelt/Natur']),
      ];

      final ranked = ranker.rank(pool, profile, now: _now);

      expect(ranked, hasLength(6));
    });
  });
}
