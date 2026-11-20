import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/bundled_cards.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';

RankedOpportunity _card(String id, {String? bundle}) => RankedOpportunity(
      opportunity: Opportunity(
        id: id,
        sourceOrg: 'openPetition',
        sourceUrl: 'https://example.org/$id',
        kind: OpportunityKind.petition,
        isAnnounced: false,
        region: 'bund',
        title: id,
        summary: id,
        affectedTags: const [],
        werteRelevanz: const {},
        proArgumente: const [],
        contraArgumente: const [],
        personalImpactSnippets: const {},
        firstSeenAt: DateTime(2026, 11, 1),
        bundle: bundle == null
            ? null
            : OpportunityBundle(
                id: bundle,
                header: 'h',
                title: 't',
                summary: 's',
                label: id,
                difference: 'd',
              ),
      ),
      matchedSnippet: null,
      werteAlignment: 0.5,
    );

List<String> _ids(List<RankedOpportunity> cards) => [
      for (final card in cards)
        card.isBundle
            ? card.options.map((o) => o.opportunity.id).join('+')
            : card.opportunity.id,
    ];

void main() {
  final ranked = [
    _card('a'),
    _card('b1', bundle: 'B'),
    _card('c'),
    _card('b2', bundle: 'B'),
    _card('lonely', bundle: 'L'),
  ];

  test('a bundle sits where its best option ranked', () {
    expect(_ids(bundleCards(ranked)), ['a', 'b1+b2', 'c', 'lonely']);
  });

  test('a bundle with one option left in the pool is a plain card', () {
    final cards = bundleCards(ranked);
    expect(cards.last.isBundle, isFalse);
  });

  test('a bundle stays while any option is open', () {
    expect(_ids(bundleCards(ranked, doneIds: {'b1', 'a'})), [
      'b1+b2',
      'c',
      'lonely',
    ]);
    expect(_ids(bundleCards(ranked, doneIds: {'b1', 'b2'})), [
      'a',
      'c',
      'lonely',
    ]);
  });
}
