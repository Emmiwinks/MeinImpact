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
    // Hard exclusions
    final actionTopics = action.topics.toSet();
    final hasMatchingTopic = profile.topics.any(actionTopics.contains);
    final isBlacklisted = profile.blacklist.any(actionTopics.contains);
    if (!hasMatchingTopic || isBlacklisted) {
      return ActionRecommendation(action: action, score: 0, reasons: const []);
    }

    final reasons = <String>[];

    // 1. Topic match: fraction of action topics in user's whitelist
    final matched = actionTopics.where(profile.topics.contains).length;
    final topicMatch = matched / actionTopics.length.clamp(1, 10);
    if (topicMatch > 0) {
      reasons.add('Passt zu deinen Themen.');
    }

    // 2. Werte match (0.0–1.0) — neutral 0.5 when no axes overlap
    final werteMatch = profile.answeredCount >= 4
        ? _computeWerteMatch(action, profile)
        : 0.5;

    // 3. Urgency
    final urgencyScore = switch (action.urgency) {
      'high' => 1.0,
      'mid' => 0.6,
      _ => 0.3,
    };
    if (urgencyScore >= 0.6) reasons.add('Deadline ist bald.');

    // 4. Deadline proximity bonus (0.0–0.4)
    final deadlineBonus = action.deadline == null
        ? 0.0
        : (1.0 -
                (action.deadline!.difference(DateTime.now()).inDays / 60.0))
            .clamp(0.0, 0.4);

    // 5. Momentum (0.05 weight, no data yet → 0)
    const momentumBonus = 0.0;

    final raw = topicMatch * 0.35 +
        werteMatch * 0.25 +
        urgencyScore * 0.25 +
        deadlineBonus * 0.10 +
        momentumBonus * 0.05;

    if (reasons.isEmpty) reasons.add('Aktuell verfügbare Maßnahme.');
    return ActionRecommendation(
      action: action,
      score: (raw * 100).round(),
      reasons: reasons,
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
