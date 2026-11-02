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
    this.maxWeight = 1.0,
    this.halfLife = const Duration(days: 14),
    this.neutralBand = 0.05,
    this.reasonThreshold = 0.15,
    this.rankingInfluence = 0.3,
    this.explorationInterval = 5,
  });

  // Weight gained by a topic when its card is opened / acted on.
  final double openedDelta;
  final double actedDelta;
  // Weights are clamped to -maxWeight..+maxWeight.
  final double maxWeight;
  // Time for a weight to fall to half its value. 14 days follows a change
  // of taste in ~12 days (calibration test); 30 days took 25.
  final Duration halfLife;
  // Below this magnitude a topic counts as "no opinion" (unexplored).
  final double neutralBand;
  // From this weight a topic is strong enough to be named on a card.
  final double reasonThreshold;
  // How much appeal (0-1 scale) a topic at full weight is worth in ranking.
  final double rankingInfluence;
  // Every n-th slot goes to an unexplored topic; 0 turns exploration off.
  final int explorationInterval;

  double deltaFor(InterestSignal signal) => switch (signal) {
        InterestSignal.opened => openedDelta,
        InterestSignal.acted => actedDelta,
      };
}
