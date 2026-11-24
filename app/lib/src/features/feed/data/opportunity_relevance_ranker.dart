import 'dart:math';

import '../domain/interest_config.dart';
import '../domain/interest_weights.dart';
import '../domain/locality_config.dart';
import '../domain/opportunity.dart';
import '../domain/user_profile.dart';

/// What each signal added to a card's blended score (see
/// OpportunityRelevanceRanker), kept per card so a thrown-away card can
/// tell the beta feedback why it was dealt.
class ScoreParts {
  const ScoreParts({
    this.appeal = 0,
    this.situation = 0,
    this.interest = 0,
    this.locality = 0,
    this.haltung = 0,
    this.exploration = false,
  });

  final double appeal;
  final double situation;
  final double interest;
  final double locality;
  final double haltung;
  // The card took an exploration slot, not its place by score.
  final bool exploration;

  double get total => appeal + situation + interest + locality + haltung;

  /// The ranking snapshot of POST /v1/feedback/card, for the card at
  /// [position] in the hand (0 = first).
  Map<String, Object?> toFeedback({required int position}) => {
        'position': position,
        'score': total,
        'appeal': appeal,
        'situation': situation,
        'interest': interest,
        'locality': locality,
        'haltung': haltung,
        'exploration': exploration,
      };

  ScoreParts asExploration() => ScoreParts(
        appeal: appeal,
        situation: situation,
        interest: interest,
        locality: locality,
        haltung: haltung,
        exploration: true,
      );
}

/// An opportunity plus the on-device-computed relevance facts the UI needs,
/// computed once here rather than per widget rebuild.
class RankedOpportunity {
  const RankedOpportunity({
    required this.opportunity,
    required this.matchedSnippet,
    this.interestTag,
    this.matchedLebenslage,
    this.matchStrength = 0,
    this.haltung = 0,
    this.inOwnNeighbourhood = false,
    this.parts = const ScoreParts(),
    this.options = const [],
  });

  /// This card as the face of a bundle: [options] are all its members,
  /// itself included, best ranked first (see bundleCards).
  RankedOpportunity withOptions(List<RankedOpportunity> options) =>
      _copy(options: options);

  RankedOpportunity _copy({
    ScoreParts? parts,
    List<RankedOpportunity>? options,
  }) {
    return RankedOpportunity(
      opportunity: opportunity,
      matchedSnippet: matchedSnippet,
      interestTag: interestTag,
      matchedLebenslage: matchedLebenslage,
      matchStrength: matchStrength,
      haltung: haltung,
      inOwnNeighbourhood: inOwnNeighbourhood,
      parts: parts ?? this.parts,
      options: options ?? this.options,
    );
  }

  final Opportunity opportunity;
  // What ranked this card where it is.
  final ScoreParts parts;
  // The bundle's members when this card bundles several; empty otherwise.
  final List<RankedOpportunity> options;
  bool get isBundle => options.length >= 2;
  // The learned favourite topic that ranked this card up, if one is strong
  // enough to name ("Weil du dich für Mobilität interessierst").
  final String? interestTag;
  // The card's main Lebenslage (the first one enrichment listed) when the
  // user picked it: the only group a card names in its hint, so an odd
  // secondary tag never shows. Private ones are never named at all.
  final String? matchedLebenslage;
  // 0-1: how strongly the card concerns the user's situation. A personal
  // snippet or a Lebenslage counts by how rare it is in the pool, so a broad
  // one ("Mieter" on a sixth of the cards) moves little and a specific one
  // ("Pflegende Angehörige") a lot.
  final double matchStrength;

  // The personal_impact_snippet matching the user's Lebenslagen (through
  // their snippet keys), if any: the feed card's hook line (else the
  // opportunity's summary).
  final String? matchedSnippet;

  bool get isSituationMatch => matchStrength > 0;

  // -1..1: how the card fits the user's stance. On a petition, whether they
  // would likely sign it; on an open procedure (a council decision, a
  // consultation, a plan), only how much they care, since one can take
  // part on either side. 0 = no signal.
  final double haltung;

  // A neighbourhood's card (Ortschaftsrat, Stadtbezirksbeirat ...) for the
  // neighbourhood the user lives in.
  final bool inOwnNeighbourhood;

  /// Whether the card concerns the user personally, not just by appeal:
  /// what the hand's local slot asks of a city's card (see mixHand).
  bool get isPersonal => isSituationMatch || haltung > 0 || inOwnNeighbourhood;
}

/// Orders the open opportunities by on-device relevance with one blended
/// score, so no signal can lock out another:
///   appeal (easy, everyday cards first: quick wins)
///   + [InterestConfig.matchBonus] scaled by the match strength, if the
///     card concerns the user's situation (a personal snippet or one of
///     their Lebenslagen, each weighted by its rarity in the pool)
///   + nearness to home: a city's or neighbourhood's matters sink with
///     distance from where the user lives, their own neighbourhood's rise
///     ([LocalityConfig])
///   + learned topic interest, scaled by [InterestConfig.rankingInfluence]
///   + Haltung, scaled by [InterestConfig.haltungInfluence]: the
///     Werteprofil where the card carries questionnaire statements, the
///     Stadthaushalt where it moves money.
/// Never drops an opportunity, only reorders; which levels the hand mixes
/// is mixHand's job. No recency or support-count component: the server only
/// serves opportunities that are still open, and support counts are
/// informational, never a ranking signal.
///
/// Once the user has learned interests, every
/// [InterestConfig.explorationInterval]th slot goes to the best card from a
/// topic they have no opinion on yet, so the feed does not close into a
/// bubble. All interest tuning comes from [interestConfig].
class OpportunityRelevanceRanker {
  const OpportunityRelevanceRanker({
    this.interestConfig = const InterestConfig(),
    this.localityConfig = const LocalityConfig(),
  });

  final InterestConfig interestConfig;
  final LocalityConfig localityConfig;

  static const _minAnsweredForWerteMatch = 4;
  // The even share of a Stadthaushalt pot: 20 coins over 8 pots.
  static const _evenCoins = 2.5;

  List<RankedOpportunity> rank(
    List<Opportunity> pool,
    UserProfile profile, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final interests = profile.interests;
    final rarity = _rarity(pool, (o) => o.lebenslagen);
    final snippetRarity = _rarity(pool, (o) => o.personalImpactSnippets.keys);
    final ranked = [
      for (final o in pool)
        _scored(_rankOne(o, profile, at, rarity, snippetRarity), profile, at),
    ]..sort((a, b) => b.parts.total.compareTo(a.parts.total));
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
          rest[pick] = rest[pick]._copy(
            parts: rest[pick].parts.asExploration(),
          );
        }
      }
      result.add(rest.removeAt(take));
    }
    return result;
  }

  RankedOpportunity _scored(
    RankedOpportunity r,
    UserProfile profile,
    DateTime now,
  ) {
    return r._copy(
      parts: ScoreParts(
        appeal: r.opportunity.appeal,
        situation: interestConfig.matchBonus * r.matchStrength,
        interest: interestConfig.rankingInfluence *
            profile.interests.interestIn(
              r.opportunity.affectedTags,
              now,
              interestConfig,
            ),
        locality: localityConfig.adjustment(r.opportunity, profile.home),
        haltung: interestConfig.haltungInfluence * r.haltung,
      ),
    );
  }

  /// Weight per key (a Lebenslage, a snippet key) from how many cards in
  /// the pool carry it: 1 for a key on a single card, falling to
  /// [InterestConfig.minMatchWeight] for one on every card (normalized
  /// inverse document frequency). Computed from the current pool, so it
  /// adapts as the data changes.
  Map<String, double> _rarity(
    List<Opportunity> pool,
    Iterable<String> Function(Opportunity) keysOf,
  ) {
    final counts = <String, int>{};
    for (final opportunity in pool) {
      for (final key in keysOf(opportunity).toSet()) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final minWeight = interestConfig.minMatchWeight;
    if (pool.length < 2) return {for (final key in counts.keys) key: 1.0};
    return {
      for (final MapEntry(key: key, value: count) in counts.entries)
        key: minWeight +
            (1 - minWeight) * log(pool.length / count) / log(pool.length),
    };
  }

  RankedOpportunity _rankOne(
    Opportunity opportunity,
    UserProfile profile,
    DateTime now,
    Map<String, double> rarity,
    Map<String, double> snippetRarity,
  ) {
    final snippetKey = _matchedSnippetKey(opportunity, profile);
    var strength = snippetKey == null ? 0.0 : snippetRarity[snippetKey] ?? 1.0;
    for (final id in opportunity.lebenslagen) {
      if (profile.lebenslagen.contains(id)) {
        strength = max(strength, rarity[id] ?? 1.0);
      }
    }
    final main =
        opportunity.lebenslagen.isEmpty ? null : opportunity.lebenslagen.first;
    final area = opportunity.umkreis;
    final home = profile.home;
    return RankedOpportunity(
      opportunity: opportunity,
      matchedSnippet: snippetKey == null
          ? null
          : opportunity.personalImpactSnippets[snippetKey],
      matchedLebenslage:
          main != null && profile.lebenslagen.contains(main) ? main : null,
      matchStrength: strength,
      haltung: _haltung(opportunity, profile),
      inOwnNeighbourhood: opportunity.reichweite == 'nachbarschaft' &&
          area != null &&
          home != null &&
          nearness(area, home) == 1,
      interestTag: profile.interests.reasonTag(
        opportunity.affectedTags,
        now,
        interestConfig,
      ),
    );
  }

  String? _matchedSnippetKey(Opportunity opportunity, UserProfile profile) {
    if (opportunity.personalImpactSnippets.isEmpty) return null;
    for (final key in profile.snippetKeys) {
      if (opportunity.personalImpactSnippets.containsKey(key)) return key;
    }
    return null;
  }

  /// The mean of whichever stance signals the card carries, -1..1. A
  /// petition can only be supported, so there the direction counts; on an
  /// open procedure only how strongly the user feels, so the card rises
  /// for both sides.
  double _haltung(Opportunity opportunity, UserProfile profile) {
    final petition = opportunity.kind == OpportunityKind.petition;
    final parts = [
      _werteSignal(opportunity, profile, petition: petition),
      _geldSignal(opportunity, profile, petition: petition),
    ].nonNulls;
    if (parts.isEmpty) return 0;
    return parts.reduce((a, b) => a + b) / parts.length;
  }

  /// Per questionnaire statement on the card: the user's answer s (-2..2)
  /// times the card's side v (-1 left, +1 right), halved to -1..1.
  double? _werteSignal(
    Opportunity opportunity,
    UserProfile profile, {
    required bool petition,
  }) {
    if (profile.answeredCount < _minAnsweredForWerteMatch) return null;
    final values = <double>[];
    opportunity.werteRelevanz.forEach((key, side) {
      final answer = profile.werte[key] ?? 0;
      if (answer == 0 || side == 0) return;
      values.add(petition ? answer * side / 2 : answer.abs() / 2);
    });
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Per budget area on the card: how far the user's coins in that pot lie
  /// from the even share, rising evenly up to their own fullest pot (+1)
  /// and down to an empty one (-1). On an open procedure only what the user
  /// favours counts, not what they gave nothing.
  double? _geldSignal(
    Opportunity opportunity,
    UserProfile profile, {
    required bool petition,
  }) {
    final coins = profile.prioritaeten;
    if (coins.isEmpty || opportunity.geld.isEmpty) return null;
    final fullest = coins.values.reduce(max);
    double tilt(int pot) => pot >= _evenCoins
        ? (fullest > _evenCoins
            ? (pot - _evenCoins) / (fullest - _evenCoins)
            : 0)
        : (pot - _evenCoins) / _evenCoins;
    final values = [
      for (final effect in opportunity.geld)
        petition
            ? tilt(coins[effect.bereich] ?? 0) * effect.richtung
            : max(0.0, tilt(coins[effect.bereich] ?? 0)),
    ];
    return values.reduce((a, b) => a + b) / values.length;
  }
}
