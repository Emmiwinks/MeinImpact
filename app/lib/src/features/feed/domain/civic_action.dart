class CivicAction {
  const CivicAction({
    required this.id,
    required this.title,
    required this.actionType,
    required this.summary,
    required this.region,
    required this.effortMinutes,
    required this.impactHint,
    required this.sourceUrl,
    this.deadline,
    this.urgency = 'low',
    this.werteRelevanz = const {},
  });

  factory CivicAction.fromJson(Map<String, Object?> json) {
    final deadlineStr = json['deadline'] as String?;
    final werteRaw = json['werte_relevanz'] as Map<String, Object?>?;
    return CivicAction(
      id: json['id'] as String,
      title: json['title'] as String,
      actionType: json['action_type'] as String,
      summary: json['summary'] as String,
      region: json['region'] as String?,
      effortMinutes: json['effort_minutes'] as int,
      impactHint: json['impact_hint'] as String,
      sourceUrl: json['source_url'] as String,
      deadline: deadlineStr != null ? DateTime.parse(deadlineStr) : null,
      urgency: json['urgency'] as String? ?? 'low',
      werteRelevanz: werteRaw != null
          ? werteRaw.map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {},
    );
  }

  final String id;
  final String title;
  final String actionType;
  final String summary;
  final String? region;
  final int effortMinutes;
  final String impactHint;
  final String sourceUrl;
  final DateTime? deadline;
  final String urgency;
  final Map<String, double> werteRelevanz;
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
