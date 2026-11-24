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

InterestWeights _record(
  InterestWeights weights,
  String tag,
  InterestSignal signal,
) =>
    weights.record([tag], signal, _now, _config);

void main() {
  group('Thema interessiert mich nicht', () {
    test('after liking moves the same one number down', () {
      var weights = const InterestWeights();
      for (var i = 0; i < 2; i++) {
        weights = _record(weights, 'Sicherheit', InterestSignal.acted);
      }
      weights = _record(weights, 'Sicherheit', InterestSignal.notInterested);

      expect(
        weights.weightOf('Sicherheit', _now, _config),
        closeTo(0.6 - 0.5, 1e-9),
      );
    });

    test('ranks a topic down but never hides it', () {
      final profile = UserProfile(
        interests: _record(
          const InterestWeights(),
          'Sicherheit',
          InterestSignal.notInterested,
        ),
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
      weights = _record(weights, 'Wohnen/Miete', InterestSignal.acted);
      weights = _record(weights, 'Wohnen/Miete', InterestSignal.acted);
      weights = _record(weights, 'Umwelt/Natur', InterestSignal.acted);
      weights = _record(weights, 'Bildung/Schule', InterestSignal.opened);
      weights = _record(weights, 'Sicherheit', InterestSignal.notInterested);

      expect(
        weights.favourites(_now, _config),
        ['Wohnen/Miete', 'Umwelt/Natur'],
      );
    });

    test('a forgotten topic is neutral again', () {
      final weights =
          _record(const InterestWeights(), 'Wohnen/Miete', InterestSignal.acted)
              .forget('Wohnen/Miete', _now, _config);

      expect(weights.weightOf('Wohnen/Miete', _now, _config), 0);
      expect(weights.favourites(_now, _config), isEmpty);
    });
  });
}
