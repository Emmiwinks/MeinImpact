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
  });

  final Opportunity opportunity;
  // The learned favourite topic that ranked this card up, if one is strong
  // enough to name ("Weil du dich für Mobilität interessierst").
  final String? interestTag;
  // A Lebenslage the user picked that this card concerns, if any (the
  // catalog id; private ones are matched but never named on the card).
  final String? matchedLebenslage;

  // The personal_impact_snippet matching the user's Lebenslagen (through
  // their snippet keys), if any: the feed card's hook line (else the
  // opportunity's summary).
  final String? matchedSnippet;

  bool get isSituationMatch =>
      matchedSnippet != null || matchedLebenslage != null;
  // 0.0-1.0, 0.5 = neutral/no signal (opportunity has no relevant axis, or
  // profile isn't answered enough to have an opinion).
  final double werteAlignment;
}

/// Orders the open opportunities by on-device relevance with one blended
/// score, so no signal can lock out another:
///   appeal (easy, everyday cards first: quick wins)
///   + [InterestConfig.matchBonus] if the card concerns one of the user's
///     Lebenslagen (directly, or through a personal snippet)
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
    final ranked = pool.map((o) => _rankOne(o, profile, at)).toList();
    double score(RankedOpportunity r) =>
        r.opportunity.appeal +
        (r.isSituationMatch ? interestConfig.matchBonus : 0) +
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

  RankedOpportunity _rankOne(
    Opportunity opportunity,
    UserProfile profile,
    DateTime now,
  ) {
    return RankedOpportunity(
      opportunity: opportunity,
      matchedSnippet: _matchedSnippetFor(opportunity, profile),
      matchedLebenslage: _matchedLebenslageFor(opportunity, profile),
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

  String? _matchedLebenslageFor(Opportunity opportunity, UserProfile profile) {
    for (final id in opportunity.lebenslagen) {
      if (profile.lebenslagen.contains(id)) return id;
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
