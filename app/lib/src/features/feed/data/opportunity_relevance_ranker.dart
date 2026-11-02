import 'dart:math';

import '../domain/interest_config.dart';
import '../domain/interest_weights.dart';
import '../domain/opportunity.dart';
import '../domain/user_profile.dart';

/// An opportunity plus the on-device-computed relevance facts the UI needs,
/// computed once here rather than per widget rebuild.
class RankedOpportunity {
  const RankedOpportunity({
    required this.opportunity,
    required this.matchedSnippet,
    required this.werteAlignment,
    this.interestTag,
    this.matchedLebenslage,
    this.matchStrength = 0,
  });

  final Opportunity opportunity;
  // The learned favourite topic that ranked this card up, if one is strong
  // enough to name ("Weil du dich für Mobilität interessierst").
  final String? interestTag;
  // The card's main Lebenslage (the first one enrichment listed) when the
  // user picked it: the only group a card names in its hint, so an odd
  // secondary tag never shows. Private ones are never named at all.
  final String? matchedLebenslage;
  // 0-1: how strongly the card concerns the user's situation. A personal
  // snippet counts fully; a Lebenslage counts by how rare it is in the
  // pool, so a broad group ("Eltern" on a quarter of the cards) moves little
  // and a specific one ("Pflegende Angehörige") a lot.
  final double matchStrength;

  // The personal_impact_snippet matching the user's Lebenslagen (through
  // their snippet keys), if any: the feed card's hook line (else the
  // opportunity's summary).
  final String? matchedSnippet;

  bool get isSituationMatch => matchStrength > 0;
  // 0.0-1.0, 0.5 = neutral/no signal (opportunity has no relevant axis, or
  // profile isn't answered enough to have an opinion).
  final double werteAlignment;
}

/// Orders the open opportunities by on-device relevance with one blended
/// score, so no signal can lock out another:
///   appeal (easy, everyday cards first: quick wins)
///   + [InterestConfig.matchBonus] scaled by the match strength, if the
///     card concerns the user's situation (a personal snippet, or one of
///     their Lebenslagen weighted by its rarity in the pool)
///   + learned topic interest, scaled by [InterestConfig.rankingInfluence].
/// Ties fall back to Werteprofil alignment. (A hard "matched first" tier
/// used to sit above all of this; with ~45% of cards matched it made
/// learned interests in unmatched topics invisible.)
/// Never drops an opportunity, only reorders. No recency or support-count
/// component: the server only serves opportunities that are still open,
/// and support counts are informational, never a ranking signal.
///
/// Once the user has learned interests, every
/// [InterestConfig.explorationInterval]th slot goes to the best card from a
/// topic they have no opinion on yet, so the feed does not close into a
/// bubble. All interest tuning comes from [interestConfig].
class OpportunityRelevanceRanker {
  const OpportunityRelevanceRanker({
    this.interestConfig = const InterestConfig(),
  });

  final InterestConfig interestConfig;

  static const _minAnsweredForWerteMatch = 4;

  List<RankedOpportunity> rank(
    List<Opportunity> pool,
    UserProfile profile, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final interests = profile.interests;
    final rarity = _rarity(pool);
    final ranked = pool.map((o) => _rankOne(o, profile, at, rarity)).toList();
    double score(RankedOpportunity r) =>
        r.opportunity.appeal +
        interestConfig.matchBonus * r.matchStrength +
        interestConfig.rankingInfluence *
            interests.interestIn(
              r.opportunity.affectedTags,
              at,
              interestConfig,
            );
    ranked.sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      if (byScore != 0) return byScore;
      return b.werteAlignment.compareTo(a.werteAlignment);
    });
    if (interestConfig.explorationInterval <= 0 ||
        !interests.hasSignal(at, interestConfig)) {
      return ranked;
    }
    return _withExploration(ranked, interests, at);
  }

  List<RankedOpportunity> _withExploration(
    List<RankedOpportunity> sorted,
    InterestWeights interests,
    DateTime now,
  ) {
    final rest = List.of(sorted);
    final result = <RankedOpportunity>[];
    // Topics already surfaced by an exploration slot: the next one prefers a
    // different topic so exploration widens the feed instead of repeating.
    final explored = <String>{};
    bool isNew(RankedOpportunity r) =>
        !r.opportunity.affectedTags.every(explored.contains);
    while (rest.isNotEmpty) {
      var take = 0;
      if ((result.length + 1) % interestConfig.explorationInterval == 0) {
        bool unexplored(RankedOpportunity r) => interests.isUnexplored(
              r.opportunity.affectedTags,
              now,
              interestConfig,
            );
        var pick = rest.indexWhere((r) => unexplored(r) && isNew(r));
        if (pick < 0) pick = rest.indexWhere(unexplored);
        if (pick >= 0) {
          take = pick;
          explored.addAll(rest[pick].opportunity.affectedTags);
        }
      }
      result.add(rest.removeAt(take));
    }
    return result;
  }

  /// Weight per Lebenslage from how many cards in the pool carry it: 1 for a
  /// group on a single card, falling to [InterestConfig.minMatchWeight] for
  /// one on every card (normalized inverse document frequency). Computed
  /// from the current pool, so it adapts as the data changes.
  Map<String, double> _rarity(List<Opportunity> pool) {
    final counts = <String, int>{};
    for (final opportunity in pool) {
      for (final id in opportunity.lebenslagen.toSet()) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final minWeight = interestConfig.minMatchWeight;
    if (pool.length < 2) return {for (final id in counts.keys) id: 1.0};
    return {
      for (final MapEntry(key: id, value: count) in counts.entries)
        id: minWeight +
            (1 - minWeight) * log(pool.length / count) / log(pool.length),
    };
  }

  RankedOpportunity _rankOne(
    Opportunity opportunity,
    UserProfile profile,
    DateTime now,
    Map<String, double> rarity,
  ) {
    final snippet = _matchedSnippetFor(opportunity, profile);
    var strength = snippet != null ? 1.0 : 0.0;
    for (final id in opportunity.lebenslagen) {
      if (profile.lebenslagen.contains(id)) {
        strength = max(strength, rarity[id] ?? 1.0);
      }
    }
    final main =
        opportunity.lebenslagen.isEmpty ? null : opportunity.lebenslagen.first;
    return RankedOpportunity(
      opportunity: opportunity,
      matchedSnippet: snippet,
      matchedLebenslage:
          main != null && profile.lebenslagen.contains(main) ? main : null,
      matchStrength: strength,
      werteAlignment: _computeWerteAlignment(opportunity, profile),
      interestTag: profile.interests.reasonTag(
        opportunity.affectedTags,
        now,
        interestConfig,
      ),
    );
  }

  String? _matchedSnippetFor(Opportunity opportunity, UserProfile profile) {
    if (opportunity.personalImpactSnippets.isEmpty) return null;
    final matchingKeys = profile.snippetKeys;
    for (final key in matchingKeys) {
      final snippet = opportunity.personalImpactSnippets[key];
      if (snippet != null) return snippet;
    }
    return null;
  }

  double _computeWerteAlignment(Opportunity opportunity, UserProfile profile) {
    if (opportunity.werteRelevanz.isEmpty) return 0.5;
    if (profile.answeredCount < _minAnsweredForWerteMatch) return 0.5;

    final axes = profile.axisValues;
    double score = 0;
    int count = 0;
    opportunity.werteRelevanz.forEach((axis, relevance) {
      if (relevance == 0) return;
      final userScore = axes[axis] ?? 0.0;
      if (userScore == 0) return;
      score += (userScore * relevance).clamp(-1.0, 1.0);
      count++;
    });

    if (count == 0) return 0.5;
    return ((score / count) + 1) / 2;
  }
}
