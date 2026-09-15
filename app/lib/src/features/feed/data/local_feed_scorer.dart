import '../domain/civic_action.dart';
import '../domain/user_profile.dart';

class LocalFeedScorer {
  const LocalFeedScorer();

  static const _threshold = 0.2;

  List<ActionRecommendation> score(
    List<CivicAction> pool,
    UserProfile profile,
  ) {
    return pool
        .map((a) => _scoreAction(a, profile))
        .where((r) => r.score / 100 >= _threshold)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  ActionRecommendation _scoreAction(CivicAction action, UserProfile profile) {
    final reasons = <String>[];

    // 1. Werte match (0.0–1.0) — neutral 0.5 when profile not filled in
    final werteMatch =
        profile.answeredCount >= 4 ? _computeWerteMatch(action, profile) : 0.5;
    if (werteMatch > 0.65) reasons.add('Passt zu deinen Werten.');

    // 2. Urgency
    final urgencyScore = switch (action.urgency) {
      'high' => 1.0,
      'mid' => 0.6,
      _ => 0.3,
    };
    if (urgencyScore >= 0.6) reasons.add('Zeitkritisch — bald entschieden.');

    // 3. Deadline proximity bonus (0.0–0.4)
    final deadlineBonus = action.deadline == null
        ? 0.0
        : (1.0 - (action.deadline!.difference(DateTime.now()).inDays / 60.0))
            .clamp(0.0, 0.4);

    // 4. Momentum (from server-side imminence score; not yet passed through)
    const momentumBonus = 0.0;

    final raw = werteMatch * 0.60 +
        urgencyScore * 0.25 +
        deadlineBonus * 0.10 +
        momentumBonus * 0.05;

    if (reasons.isEmpty) reasons.add('Aktuell verfügbare Maßnahme.');
    return ActionRecommendation(
      action: action,
      score: (raw * 100).round(),
      reasons: reasons,
      werteMatchPercent: (werteMatch * 100).round(),
    );
  }

  double _computeWerteMatch(CivicAction action, UserProfile profile) {
    if (action.werteRelevanz.isEmpty) return 0.5;

    final axes = {
      'wirtschaft': profile.axisWirtschaft,
      'diplomatie': profile.axisDiplomatie,
      'freiheit': profile.axisFreiheit,
      'wandel': profile.axisWandel,
    };

    double score = 0;
    int count = 0;
    action.werteRelevanz.forEach((axis, relevance) {
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
