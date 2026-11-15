import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/interest_config.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

final _now = DateTime(2026, 11, 3);
const _config = InterestConfig();

Opportunity _opportunity(String id, List<String> tags) {
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
  );
}

InterestWeights _vote(
  InterestWeights weights,
  String tag,
  InterestSignal signal, {
  DateTime? at,
}) =>
    weights.record([tag], signal, at ?? _now, _config);

void main() {
  group('card votes', () {
    test('count in full for the one topic and fade like everything else', () {
      final weights =
          _vote(const InterestWeights(), 'Umwelt/Natur', InterestSignal.more);

      expect(weights.weightOf('Umwelt/Natur', _now, _config), 0.5);
      expect(
        weights.weightOf('Umwelt/Natur', _now.add(_config.halfLife), _config),
        closeTo(0.25, 1e-9),
      );
    });

    test('"Weniger davon" after liking moves the same one number down', () {
      var weights = const InterestWeights();
      for (var i = 0; i < 2; i++) {
        weights = weights.record(
          ['Sicherheit'],
          InterestSignal.acted,
          _now,
          _config,
        );
      }
      weights = _vote(weights, 'Sicherheit', InterestSignal.less);

      expect(
        weights.weightOf('Sicherheit', _now, _config),
        closeTo(0.6 - 0.5, 1e-9),
      );
    });

    test('"Weniger davon" ranks a topic down but never hides it', () {
      final profile = UserProfile(
        interests:
            _vote(const InterestWeights(), 'Sicherheit', InterestSignal.less),
      );
      final ranked = const OpportunityRelevanceRanker().rank(
        [
          _opportunity('less', ['Sicherheit']),
          _opportunity('n', ['Wohnen/Miete']),
        ],
        profile,
        now: _now,
      );

      expect(ranked.map((r) => r.opportunity.id), ['n', 'less']);
    });
  });

  group('favourites', () {
    test('are the topics a card may name, strongest first', () {
      var weights = const InterestWeights();
      weights = _vote(weights, 'Wohnen/Miete', InterestSignal.more);
      weights = weights.record(
        ['Umwelt/Natur'],
        InterestSignal.acted,
        _now,
        _config,
      );
      weights = weights.record(
        ['Bildung/Schule'],
        InterestSignal.opened,
        _now,
        _config,
      );
      weights = _vote(weights, 'Sicherheit', InterestSignal.less);

      expect(
        weights.favourites(_now, _config),
        ['Wohnen/Miete', 'Umwelt/Natur'],
      );
    });

    test('a forgotten topic is neutral again', () {
      final weights =
          _vote(const InterestWeights(), 'Wohnen/Miete', InterestSignal.more)
              .forget('Wohnen/Miete', _now, _config);

      expect(weights.weightOf('Wohnen/Miete', _now, _config), 0);
      expect(weights.favourites(_now, _config), isEmpty);
    });
  });

  test('levels set by hand before votes existed are folded in once', () {
    final restored = InterestWeights.fromJson(const {
      'manual': {
        'Umwelt/Natur': 'more',
        'Sicherheit': 'less',
        'Wohnen/Miete': 'kaputt',
      },
    });
    final now = restored.asOf!;

    expect(restored.weightOf('Umwelt/Natur', now, _config), 0.5);
    expect(restored.weightOf('Sicherheit', now, _config), -0.5);
    expect(restored.weightOf('Wohnen/Miete', now, _config), 0);
    expect(restored.toJson().containsKey('manual'), isFalse);
  });
}
