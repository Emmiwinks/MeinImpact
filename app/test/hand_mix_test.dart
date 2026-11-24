import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/features/feed/data/hand_mix.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';

RankedOpportunity _card(
  String id,
  String gebiet, {
  bool personal = false,
  bool exploration = false,
}) {
  return RankedOpportunity(
    opportunity: Opportunity(
      id: id,
      sourceOrg: 'src',
      sourceUrl: 'https://example.org/$id',
      kind: OpportunityKind.petition,
      isAnnounced: false,
      region: 'x',
      title: id,
      summary: id,
      affectedTags: const [],
      werteRelevanz: const {},
      proArgumente: const [],
      contraArgumente: const [],
      personalImpactSnippets: const {},
      firstSeenAt: DateTime(2026, 11, 1),
      gebiet: gebiet,
    ),
    matchedSnippet: null,
    matchStrength: personal ? 0.5 : 0,
    parts: ScoreParts(exploration: exploration),
  );
}

List<String> _ids(List<RankedOpportunity> cards) =>
    [for (final c in cards) c.opportunity.id];

void main() {
  test('no more than three cards of one level in the hand', () {
    final cards = [
      for (var i = 1; i <= 5; i++) _card('stadt$i', '14612'),
      _card('bund1', ''),
      _card('land1', '14'),
    ];

    final mixed = mixHand(cards, handSize: 5);

    expect(
      _ids(mixed).take(5),
      ['stadt1', 'stadt2', 'stadt3', 'bund1', 'land1'],
    );
    // Held-back cards follow in ranked order; nothing is dropped
    expect(_ids(mixed).skip(5), ['stadt4', 'stadt5']);
  });

  test('a local card that concerns the user takes the last slot', () {
    final cards = [
      for (var i = 1; i <= 3; i++) _card('bund$i', ''),
      _card('land1', '14'),
      _card('land2', '14'),
      _card('stadt-fern', '14612'),
      _card('stadt-dich', '14612', personal: true),
    ];

    final mixed = mixHand(cards, handSize: 5);

    expect(
      _ids(mixed).take(5),
      ['bund1', 'bund2', 'bund3', 'land1', 'stadt-dich'],
    );
    expect(_ids(mixed)[5], 'land2');
  });

  test('the local card never pushes out an exploration slot', () {
    final cards = [
      for (var i = 1; i <= 3; i++) _card('bund$i', ''),
      _card('land1', '14'),
      _card('land-neu', '14', exploration: true),
      _card('stadt-dich', '14612', personal: true),
    ];

    final mixed = mixHand(cards, handSize: 5);

    expect(
      _ids(mixed).take(5),
      ['bund1', 'bund2', 'bund3', 'land-neu', 'stadt-dich'],
    );
    expect(_ids(mixed)[5], 'land1');
  });

  test('without a local card that concerns the user, the ranking stands', () {
    final cards = [
      for (var i = 1; i <= 3; i++) _card('bund$i', ''),
      _card('land1', '14'),
      _card('land2', '14'),
      _card('stadt-fern', '14612'),
    ];

    expect(_ids(mixHand(cards, handSize: 5)).take(5), [
      'bund1',
      'bund2',
      'bund3',
      'land1',
      'land2',
    ]);
  });

  test('a short pool is left as it is', () {
    final cards = [_card('bund1', ''), _card('bund2', '')];

    expect(_ids(mixHand(cards, handSize: 5)), ['bund1', 'bund2']);
  });
}
