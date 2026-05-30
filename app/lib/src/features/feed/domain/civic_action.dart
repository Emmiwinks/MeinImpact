class CivicAction {
  const CivicAction({
    required this.id,
    required this.title,
    required this.actionType,
    required this.summary,
    required this.topics,
    required this.region,
    required this.effortMinutes,
    required this.impactHint,
    required this.sourceUrl,
  });

  factory CivicAction.fromJson(Map<String, Object?> json) {
    return CivicAction(
      id: json['id'] as String,
      title: json['title'] as String,
      actionType: json['action_type'] as String,
      summary: json['summary'] as String,
      topics: (json['topics'] as List<Object?>).cast<String>(),
      region: json['region'] as String?,
      effortMinutes: json['effort_minutes'] as int,
      impactHint: json['impact_hint'] as String,
      sourceUrl: json['source_url'] as String,
    );
  }

  final String id;
  final String title;
  final String actionType;
  final String summary;
  final List<String> topics;
  final String? region;
  final int effortMinutes;
  final String impactHint;
  final String sourceUrl;
}

class ActionRecommendation {
  const ActionRecommendation({
    required this.action,
    required this.score,
    required this.reasons,
  });

  factory ActionRecommendation.fromJson(Map<String, Object?> json) {
    return ActionRecommendation(
      action: CivicAction.fromJson(json['action'] as Map<String, Object?>),
      score: json['score'] as int,
      reasons: (json['reasons'] as List<Object?>).cast<String>(),
    );
  }

  final CivicAction action;
  final int score;
  final List<String> reasons;
}
