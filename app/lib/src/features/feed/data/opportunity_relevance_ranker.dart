import '../domain/opportunity.dart';
import '../domain/user_profile.dart';

/// An opportunity plus the two on-device-computed relevance facts the UI
/// needs — computed once here rather than recomputed per widget rebuild.
class RankedOpportunity {
  const RankedOpportunity({
    required this.opportunity,
    required this.matchedSnippet,
    required this.werteAlignment,
  });

  final Opportunity opportunity;
  // The personal_impact_snippet matching the user's Betroffenheitsprofil,
  // if any — the feed card's hook line, per the confirmed design ("personal
  // snippet when matched, else plain_language_summary").
  final String? matchedSnippet;
  // 0.0-1.0, 0.5 = neutral/no signal (opportunity has no relevant axis, or
  // profile isn't answered enough to have an opinion).
  final double werteAlignment;
}

/// Orders the current run's opportunities by on-device relevance —
/// Betroffenheitsprofil tag-match first, then Werteprofil alignment (see
/// the rebuild plan section 5). Never drops an opportunity — "no
/// opportunity is hard-excluded by tag or cluster mismatch on the client,
/// only reordered". No recency component: the pool endpoint already
/// scopes to exactly the current run, so there's nothing left to sort by
/// staleness/momentum (see project_dip_to_tavily_pivot.md, "one run, one
/// feed").
class OpportunityRelevanceRanker {
  const OpportunityRelevanceRanker();

  static const _minAnsweredForWerteMatch = 4;

  List<RankedOpportunity> rank(
    List<Opportunity> pool,
    UserProfile profile,
  ) {
    final ranked = pool.map((o) => _rankOne(o, profile)).toList();
    ranked.sort((a, b) {
      final byMatch = _matchRank(b).compareTo(_matchRank(a));
      if (byMatch != 0) return byMatch;
      return b.werteAlignment.compareTo(a.werteAlignment);
    });
    return ranked;
  }

  RankedOpportunity _rankOne(Opportunity opportunity, UserProfile profile) {
    return RankedOpportunity(
      opportunity: opportunity,
      matchedSnippet: _matchedSnippetFor(opportunity, profile),
      werteAlignment: _computeWerteAlignment(opportunity, profile),
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
