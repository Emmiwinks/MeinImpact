import 'opportunity_relevance_ranker.dart';

/// Folds the members of each bundle into one card, in rank order: the card
/// sits where its best member ranked and carries all members as options.
/// A bundle with only one member left in the pool is a plain card.
///
/// Cards whose options are all in [doneIds] leave the hand; a bundle stays
/// while any option is still open, so the others remain one tap away. A
/// plain card leaves once done, as before.
List<RankedOpportunity> bundleCards(
  List<RankedOpportunity> ranked, {
  Set<String> doneIds = const {},
}) {
  final members = <String, List<RankedOpportunity>>{};
  for (final card in ranked) {
    final bundle = card.opportunity.bundle;
    if (bundle != null) (members[bundle.id] ??= []).add(card);
  }
  final placed = <String>{};
  final cards = <RankedOpportunity>[];
  for (final card in ranked) {
    final bundle = card.opportunity.bundle;
    final options = bundle == null ? null : members[bundle.id]!;
    if (options == null || options.length < 2) {
      if (!doneIds.contains(card.opportunity.id)) cards.add(card);
      continue;
    }
    if (!placed.add(bundle!.id)) continue;
    if (options.every((o) => doneIds.contains(o.opportunity.id))) continue;
    cards.add(card.withOptions(options));
  }
  return cards;
}
