class CivicAction {
  const CivicAction({
    required this.id,
    required this.title,
    required this.actionType,
    required this.summary,
    required this.region,
    required this.sourceUrl,
    required this.topicId,
    this.deadline,
    this.urgency = 'low',
    this.werteRelevanz = const {},
    this.proArgumente = const [],
    this.contraArgumente = const [],
    this.engagementState = 'C',
    this.stateReason,
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
      sourceUrl: json['source_url'] as String,
      // Falls back to id: a topic_id is only meaningfully absent for
      // construction sites that don't care (dummy/demo data) — every real
      // pipeline-sourced action always has one, see backend merge.py.
      topicId: json['topic_id'] as String? ?? json['id'] as String,
      deadline: deadlineStr != null ? DateTime.parse(deadlineStr) : null,
      urgency: json['urgency'] as String? ?? 'low',
      werteRelevanz: werteRaw != null
          ? werteRaw.map((k, v) => MapEntry(k, (v as num).toDouble()))
          : const {},
      proArgumente:
          (json['pro_argumente'] as List<Object?>?)?.cast<String>() ?? const [],
      contraArgumente:
          (json['contra_argumente'] as List<Object?>?)?.cast<String>() ??
              const [],
      engagementState: json['engagement_state'] as String? ?? 'C',
      stateReason: json['state_reason'] as String?,
    );
  }

  final String id;
  final String title;
  final String actionType;
  final String summary;
  final String? region;
  final String sourceUrl;
  final String topicId;
  final DateTime? deadline;
  final String urgency;
  final Map<String, double> werteRelevanz;
  final List<String> proArgumente;
  final List<String> contraArgumente;
  // Real, pipeline-derived facts — see specs/data/ingestion-pipeline.md
  // "Engagement States". Deliberately no invented score/time-estimate
  // fields here (effort_minutes/impact_hint were canned lookup-table text,
  // not observed facts — removed rather than displayed).
  final String engagementState; // "A" | "B" | "C"
  final String? stateReason;
}

class ActionRecommendation {
  const ActionRecommendation({
    required this.action,
    required this.score,
    required this.reasons,
    this.werteMatchPercent,
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
  // Real KPI, shown on demand (topic detail, not the feed list) — how well
  // this option's werte_relevanz matches the device-side value profile.
  // Null only when a recommendation wasn't built by LocalFeedScorer (e.g.
  // this JSON factory, used by tests/deprecated endpoints) and there is no
  // real computed value to show.
  final int? werteMatchPercent;
}
