import 'interest_weights.dart';

/// Every tuning number of the interest learning and its ranking effect, in
/// one place. Nothing else hard-codes them: change a value here (or pass a
/// different config in a test, a debug build or later a remote config) and
/// both the learning and the ranker follow. The defaults are a starting
/// point; `test/interest_calibration_test.dart` replays synthetic users
/// against them so a change can be judged before it ships.
class InterestConfig {
  const InterestConfig({
    this.openedDelta = 0.1,
    this.actedDelta = 0.3,
    this.moreDelta = 0.5,
    this.lessDelta = -0.5,
    this.maxWeight = 1.0,
    this.halfLife = const Duration(days: 30),
    this.neutralBand = 0.05,
    this.reasonThreshold = 0.15,
    this.matchBonus = 0.5,
    this.minMatchWeight = 0.3,
    this.rankingInfluence = 0.3,
    this.haltungInfluence = 0.3,
    this.explorationInterval = 5,
  });

  // Weight gained by a topic when its card is opened / acted on.
  final double openedDelta;
  final double actedDelta;
  // Weight a "Mehr davon" / "Weniger davon" on a card gives its topic.
  final double moreDelta;
  final double lessDelta;
  // Weights are clamped to -maxWeight..+maxWeight.
  final double maxWeight;
  // Time for a weight to fall to half its value. 30 days keeps a "Weniger
  // davon" for about two months; behaviour alone then follows a change of
  // taste in ~25 days instead of ~12 at 14 days (calibration test), and a
  // card vote speeds that up.
  final Duration halfLife;
  // Below this magnitude a topic counts as "no opinion" (unexplored).
  final double neutralBand;
  // From this weight a topic is strong enough to be named on a card.
  final double reasonThreshold;
  // Appeal (0-1 scale) added to a card that concerns the user's situation,
  // scaled by how rare that is in the pool. The strongest signal: what
  // concerns you comes first, whatever you think of it (simulated on the
  // live pool with three personas, 2026-11-23).
  final double matchBonus;
  // Share of [matchBonus] a Lebenslage or personal snippet still earns when
  // it is on every card in the pool; rarer ones earn more, up to the full
  // bonus. (A snippet used to count fully; with one on 86 of 146 cards
  // nearly every top card was a "full" match.)
  final double minMatchWeight;
  // How much appeal (0-1 scale) a topic at full weight is worth in ranking.
  final double rankingInfluence;
  // How much appeal (0-1 scale) full Haltung is worth: the Werteprofil on
  // cards with questionnaire statements (mostly Bund/EU), the Stadthaushalt
  // on cards that move money (mostly a city's). Below [matchBonus]: as the
  // strongest signal it put four cards of one pot into a hand and dropped
  // a pensioner's own pension card.
  final double haltungInfluence;
  // Every n-th slot goes to an unexplored topic; 0 turns exploration off.
  final int explorationInterval;

  double deltaFor(InterestSignal signal) => switch (signal) {
        InterestSignal.opened => openedDelta,
        InterestSignal.acted => actedDelta,
        InterestSignal.more => moreDelta,
        InterestSignal.less => lessDelta,
      };
}
