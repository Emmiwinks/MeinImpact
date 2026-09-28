/// A civic opportunity from the Tavily-sourced backend pipeline — replaces
/// `CivicAction`/`Topic`. Unlike the old model, there is no topic/option
/// grouping: de-duplication already happened server-side (embedding
/// similarity against `decisionObject`), so one `Opportunity` is already
/// one deduplicated, standalone thing. The pool response carries
/// everything needed for both the feed card and its detail popup — no
/// follow-up request required to open an opportunity.
class Opportunity {
  const Opportunity({
    required this.id,
    required this.sourceOrg,
    required this.decisionObject,
    required this.plainLanguageTitle,
    required this.plainLanguageSummary,
    required this.affectedTags,
    required this.region,
    required this.werteRelevanz,
    required this.sourceUrl,
    required this.actionTypes,
    required this.proArgumente,
    required this.contraArgumente,
    required this.personalImpactSnippets,
    required this.retrievedAt,
    this.deadline,
    this.supportCount,
    this.supportCountAsOf,
    this.contentPublishedAt,
  });

  factory Opportunity.fromJson(Map<String, Object?> json) {
    final deadlineStr = json['deadline'] as String?;
    final supportAsOfStr = json['support_count_as_of'] as String?;
    final publishedStr = json['content_published_at'] as String?;
    final werteRaw = json['werte_relevanz'] as Map<String, Object?>? ?? {};
    final snippetsRaw =
        json['personal_impact_snippets'] as Map<String, Object?>? ?? {};

    return Opportunity(
      id: json['id'] as String,
      sourceOrg: json['source_org'] as String,
      decisionObject: json['decision_object'] as String,
      plainLanguageTitle: json['plain_language_title'] as String,
      plainLanguageSummary: json['plain_language_summary'] as String,
      affectedTags:
          (json['affected_tags'] as List<Object?>?)?.cast<String>() ?? const [],
      region: json['region'] as String,
      werteRelevanz: werteRaw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      deadline: deadlineStr != null ? DateTime.parse(deadlineStr) : null,
      supportCount: json['support_count'] as int?,
      supportCountAsOf:
          supportAsOfStr != null ? DateTime.parse(supportAsOfStr) : null,
      contentPublishedAt:
          publishedStr != null ? DateTime.parse(publishedStr) : null,
      retrievedAt: DateTime.parse(json['retrieved_at'] as String),
      sourceUrl: json['source_url'] as String,
      actionTypes:
          (json['action_types'] as List<Object?>?)?.cast<String>() ?? const [],
      proArgumente:
          (json['pro_argumente'] as List<Object?>?)?.cast<String>() ?? const [],
      contraArgumente:
          (json['contra_argumente'] as List<Object?>?)?.cast<String>() ??
              const [],
      personalImpactSnippets:
          snippetsRaw.map((k, v) => MapEntry(k, v as String)),
    );
  }

  final String id;
  // Always populated, always shown — see the rebuild plan section 1.
  final String sourceOrg;
  // Internal/dedup-oriented canonical phrasing — not shown in the UI (see
  // plainLanguageTitle/Summary for the user-facing text).
  final String decisionObject;
  final String plainLanguageTitle;
  final String plainLanguageSummary;
  final List<String> affectedTags;
  final String region;
  final Map<String, double> werteRelevanz;
  final DateTime? deadline;
  final int? supportCount;
  final DateTime? supportCountAsOf;
  final DateTime? contentPublishedAt;
  // First-seen timestamp — kept for reference, not used for feed sorting
  // (the pool endpoint already scopes to "the current run" only, see
  // OpportunityRepository; no recency sort needed on top of that).
  final DateTime retrievedAt;
  final String sourceUrl;
  // What kind of participation this specific source offers (usually one
  // value) — "petition" | "consultation" | "anfrage" | "brief".
  final List<String> actionTypes;
  final List<String> proArgumente;
  final List<String> contraArgumente;
  // "field:value" -> sentence, keyed to match
  // Betroffenheitsprofil.matchingKeys() — see that class's docstring.
  final Map<String, String> personalImpactSnippets;
}

/// The primary action button's label and semantics, driven by
/// `actionTypes.first` — confirmed design: one CTA per opportunity, not
/// one per action type (rare to have more than one, and there's only one
/// `sourceUrl` to link to regardless).
class ActionCta {
  const ActionCta({required this.label, required this.actionType});

  factory ActionCta.forOpportunity(Opportunity opportunity) {
    final type = opportunity.actionTypes.isNotEmpty
        ? opportunity.actionTypes.first
        : 'petition';
    return ActionCta(label: _labelFor(type), actionType: type);
  }

  final String label;
  final String actionType;

  static String _labelFor(String actionType) => switch (actionType) {
        'petition' => 'Petition unterschreiben',
        'consultation' => 'Jetzt mitmachen',
        'anfrage' => 'Zur Anfrage',
        'brief' => 'Zur Quelle',
        _ => 'Zur Quelle',
      };
}
