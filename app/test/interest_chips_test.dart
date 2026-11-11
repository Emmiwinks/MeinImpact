import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/interest_config.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/topic_tags.g.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/widgets/interest_chips.dart';

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

void main() {
  group('manual interest levels', () {
    test('add on top of what was learned and never decay', () {
      final weights = const InterestWeights()
          .withManual('Umwelt/Natur', InterestLevel.more);
      final later = _now.add(const Duration(days: 365));

      expect(weights.weightOf('Umwelt/Natur', later, _config), 0.6);
      expect(weights.learnedOf('Umwelt/Natur', later, _config), 0);
      expect(weights.hasSignal(later, _config), isTrue);
    });

    test('combine with learned weight, clamped to the maximum', () {
      var weights = const InterestWeights();
      for (var i = 0; i < 10; i++) {
        weights = weights.record(
          ['Umwelt/Natur'],
          InterestSignal.acted,
          _now,
          _config,
        );
      }
      weights = weights.withManual('Umwelt/Natur', InterestLevel.more);

      expect(weights.weightOf('Umwelt/Natur', _now, _config), 1.0);
      expect(
        weights
            .withManual('Umwelt/Natur', InterestLevel.less)
            .weightOf('Umwelt/Natur', _now, _config),
        closeTo(1.0 - 0.6, 1e-9),
      );
    });

    test('survive recording, a reset and a JSON round trip', () {
      final weights = const InterestWeights()
          .withManual('Umwelt/Natur', InterestLevel.more)
          .withManual('Sicherheit', InterestLevel.less)
          .record(['Wohnen/Miete'], InterestSignal.opened, _now, _config);

      final restored = InterestWeights.fromJson(weights.toJson());

      expect(restored.manual, {
        'Umwelt/Natur': InterestLevel.more,
        'Sicherheit': InterestLevel.less,
      });
      expect(
        restored.withManual('Sicherheit', null).manual,
        {'Umwelt/Natur': InterestLevel.more},
      );
      expect(
        InterestWeights.fromJson(const {
          'manual': {'Umwelt/Natur': 'kaputt'},
        }).manual,
        isEmpty,
      );
    });

    test('"weniger" ranks a topic down but never hides it', () {
      final profile = UserProfile(
        interests: const InterestWeights()
            .withManual('Sicherheit', InterestLevel.less),
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

  group('InterestChips', () {
    test('a tap cycles normal -> mehr -> weniger -> normal', () {
      expect(InterestChips.next(null), InterestLevel.more);
      expect(InterestChips.next(InterestLevel.more), InterestLevel.less);
      expect(InterestChips.next(InterestLevel.less), isNull);
    });

    testWidgets('shows every topic and reports the new level on tap',
        (tester) async {
      InterestWeights? changed;
      await tester.pumpWidget(
        MaterialApp(
          theme: miTheme(Brightness.dark),
          home: Scaffold(
            body: SingleChildScrollView(
              child: InterestChips(
                interests: const InterestWeights(),
                onChanged: (w) => changed = w,
                now: _now,
              ),
            ),
          ),
        ),
      );

      for (final tag in kTopicTags) {
        expect(find.byKey(ValueKey('topic-$tag')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('topic-Umwelt/Natur')));

      expect(changed?.manual, {'Umwelt/Natur': InterestLevel.more});
    });
  });
}
