import '../domain/interest_weights.dart';
import '../domain/opportunity.dart';
import '../domain/user_profile.dart';

/// An opportunity plus the two on-device-computed relevance facts the UI
/// needs — computed once here rather than recomputed per widget rebuild.
class RankedOpportunity {
  const RankedOpportunity({
    required this.opportunity,
    required this.matchedSnippet,
    required this.werteAlignment,
    this.interestTag,
  });

  final Opportunity opportunity;
  // The learned favourite topic that ranked this card up, if one is strong
  // enough to name ("Weil du dich für Mobilität interessierst").
  final String? interestTag;
  // The personal_impact_snippet matching the user's Betroffenheitsprofil,
  // if any: the feed card's hook line (else the opportunity's summary).
  final String? matchedSnippet;
  // 0.0-1.0, 0.5 = neutral/no signal (opportunity has no relevant axis, or
  // profile isn't answered enough to have an opinion).
  final double werteAlignment;
}

/// Orders the open opportunities by on-device relevance, in three tiers:
/// 1. Betroffenheitsprofil match (it concerns me),
/// 2. appeal: easy, everyday cards before niche or demanding ones, so the
///    feed starts with quick wins, nudged by learned topic interest,
/// 3. Werteprofil alignment.
/// Never drops an opportunity, only reorders. No recency or support-count
/// component: the server only serves opportunities that are still open,
/// and support counts are informational, never a ranking signal.
///
/// Once the user has learned interests, every [_explorationInterval]th slot
/// goes to the best card from a topic they have no opinion on yet, so the
/// feed does not close into a bubble.
class OpportunityRelevanceRanker {
  const OpportunityRelevanceRanker();

  static const _minAnsweredForWerteMatch = 4;
  // Full interest (+1) is worth this much appeal (0-1 scale).
  static const _interestInfluence = 0.3;
  static const _explorationInterval = 5;

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
        _interestInfluence *
            interests.interestIn(r.opportunity.affectedTags, at);
    ranked.sort((a, b) {
      final byMatch = _matchRank(b).compareTo(_matchRank(a));
      if (byMatch != 0) return byMatch;
      final byScore = score(b).compareTo(score(a));
      if (byScore != 0) return byScore;
      return b.werteAlignment.compareTo(a.werteAlignment);
    });
    if (!interests.hasSignal(at)) return ranked;
    return _withExploration(ranked, interests, at);
  }

  List<RankedOpportunity> _withExploration(
    List<RankedOpportunity> sorted,
    InterestWeights interests,
    DateTime now,
  ) {
    final rest = List.of(sorted);
    final result = <RankedOpportunity>[];
    while (rest.isNotEmpty) {
      var take = 0;
      if ((result.length + 1) % _explorationInterval == 0) {
        final unexplored = rest.indexWhere(
          (r) => interests.isUnexplored(r.opportunity.affectedTags, now),
        );
        if (unexplored >= 0) take = unexplored;
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
      werteAlignment: _computeWerteAlignment(opportunity, profile),
      interestTag: profile.interests.reasonTag(opportunity.affectedTags, now),
    );
  }

  int _matchRank(RankedOpportunity r) => r.matchedSnippet != null ? 1 : 0;

  String? _matchedSnippetFor(Opportunity opportunity, UserProfile profile) {
    if (opportunity.personalImpactSnippets.isEmpty) return null;
    final matchingKeys = profile.betroffenheitsprofil.matchingKeys();
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
