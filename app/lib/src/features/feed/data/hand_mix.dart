import 'dart:math';

import '../domain/opportunity.dart';
import 'opportunity_relevance_ranker.dart';

/// The pool in random order, for someone who put the questionnaire off:
/// there is nothing to rank by yet. [mixHand] still mixes the levels.
List<RankedOpportunity> shuffledPool(
  List<Opportunity> pool, {
  Random? random,
}) =>
    [
      for (final o in pool)
        RankedOpportunity(opportunity: o, matchedSnippet: null),
    ]..shuffle(random);

/// Orders [cards] (ranked, best first) so the first [handSize] mix the
/// levels: at most [maxPerEbene] of one Ebene, and one of the user's own
/// city or Kreis whenever a card there concerns them, because that is where
/// a single voice moves most. Without a profile ([anyLocal]), any city's
/// card takes that slot. Within those limits the ranking stands, so an
/// exploration slot stays where the ranker put it. Cards held back follow
/// the hand in their ranked order; nothing is dropped.
List<RankedOpportunity> mixHand(
  List<RankedOpportunity> cards, {
  required int handSize,
  int maxPerEbene = 3,
  bool anyLocal = false,
}) {
  final hand = <RankedOpportunity>[];
  final rest = <RankedOpportunity>[];
  final perEbene = <Ebene, int>{};
  for (final card in cards) {
    final ebene = card.opportunity.ebene;
    if (hand.length < handSize && (perEbene[ebene] ?? 0) < maxPerEbene) {
      hand.add(card);
      perEbene[ebene] = (perEbene[ebene] ?? 0) + 1;
    } else {
      rest.add(card);
    }
  }
  final hasLocal = hand.any((c) => c.opportunity.ebene == Ebene.kommune);
  if (!hasLocal && hand.length == handSize) {
    final local = rest.indexWhere(
      (c) => c.opportunity.ebene == Ebene.kommune && (anyLocal || c.isPersonal),
    );
    if (local >= 0) {
      // The lowest card by score makes room, never an exploration slot.
      var out = hand.lastIndexWhere((c) => !c.parts.exploration);
      if (out < 0) out = hand.length - 1;
      final dropped = hand.removeAt(out);
      hand.add(rest.removeAt(local));
      rest.insert(0, dropped);
    }
  }
  return [...hand, ...rest];
}
