/// What a person actually does with an opportunity. Mirrors the backend's
/// `ActionKind`; unknown wire values map to [other] so a new backend kind
/// never breaks an older app.
enum OpportunityKind {
  petition('petition', 'Petition', 'Petition unterschreiben'),
  consultation('consultation', 'Konsultation', 'Stellung nehmen'),
  publicDisplay('public_display', 'Planauslegung', 'Plan ansehen & mitreden'),
  survey('survey', 'Umfrage', 'An Umfrage teilnehmen'),
  event('event', 'Veranstaltung', 'Zur Veranstaltung'),
  notice('notice', 'Bekanntmachung', 'Zur Quelle'),
  other('other', 'Beteiligung', 'Zur Quelle');

  const OpportunityKind(this.wire, this.label, this.callToAction);

  final String wire;
  final String label;
  final String callToAction;

  static OpportunityKind fromWire(String? value) => values.firstWhere(
        (kind) => kind.wire == value,
        orElse: () => OpportunityKind.other,
      );
}

/// One open way to participate, read from the registry that publishes it
/// (openPetition, Beteiligungsportal Sachsen, EU "Ihre Meinung zählt",
/// WeAct). Registry facts (kind, dates, support, source) are exact; title,
/// summary, tags, werte axes, arguments and snippets come from server-side
/// enrichment. The pool response carries everything the feed card and the
/// detail view need.
class Opportunity {
  const Opportunity({
    required this.id,
    required this.sourceOrg,
    required this.sourceUrl,
    required this.kind,
    required this.isAnnounced,
    required this.region,
    required this.title,
    required this.summary,
    required this.affectedTags,
    required this.werteRelevanz,
    required this.proArgumente,
    required this.contraArgumente,
    required this.personalImpactSnippets,
    required this.firstSeenAt,
    this.locality,
    this.organizer,
    this.opensOn,
    this.closesOn,
    this.supportCount,
    this.supportGoal,
  });

  factory Opportunity.fromJson(Map<String, Object?> json) {
    final werteRaw = json['werte_relevanz'] as Map<String, Object?>? ?? {};
    final snippetsRaw =
        json['personal_impact_snippets'] as Map<String, Object?>? ?? {};

    return Opportunity(
      id: json['id'] as String,
      sourceOrg: json['source_org'] as String,
      sourceUrl: json['source_url'] as String,
      kind: OpportunityKind.fromWire(json['kind'] as String?),
      isAnnounced: json['status'] == 'announced',
      region: json['region'] as String,
      locality: json['locality'] as String?,
      organizer: json['organizer'] as String?,
      title: json['title'] as String,
      summary: json['summary'] as String,
      affectedTags: _strings(json['affected_tags']),
      werteRelevanz: werteRaw.map((k, v) => MapEntry(k, (v as num).toDouble())),
      proArgumente: _strings(json['pro_argumente']),
      contraArgumente: _strings(json['contra_argumente']),
      personalImpactSnippets:
          snippetsRaw.map((k, v) => MapEntry(k, v as String)),
      opensOn: _date(json['opens_on']),
      closesOn: _date(json['closes_on']),
      supportCount: json['support_count'] as int?,
      supportGoal: json['support_goal'] as int?,
      firstSeenAt: DateTime.parse(json['first_seen_at'] as String),
    );
  }

  final String id;
  // Display name of the publishing registry; always shown.
  final String sourceOrg;
  final String sourceUrl;
  final OpportunityKind kind;
  // Listed, but participation opens later (see [opensOn]).
  final bool isAnnounced;
  // "eu" | "bund" | "sachsen" | "dresden"
  final String region;
  // The registry's own place label, e.g. "Leipzig" or "Landeshauptstadt
  // Dresden".
  final String? locality;
  final String? organizer;
  final String title;
  final String summary;
  final List<String> affectedTags;
  final Map<String, double> werteRelevanz;
  final List<String> proArgumente;
  final List<String> contraArgumente;
  // "field:value" -> sentence, keyed to match
  // Betroffenheitsprofil.matchingKeys().
  final Map<String, String> personalImpactSnippets;
  final DateTime? opensOn;
  final DateTime? closesOn;
  // Informational only, never used for ranking.
  final int? supportCount;
  final int? supportGoal;
  final DateTime firstSeenAt;

  /// Whole days until participation closes (0 = today), or null when there
  /// is no end date or it has passed.
  int? daysLeft(DateTime now) {
    final closes = closesOn;
    if (closes == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final days = closes.difference(today).inDays;
    return days >= 0 ? days : null;
  }

  static List<String> _strings(Object? value) =>
      (value as List<Object?>?)?.cast<String>() ?? const [];

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.parse(value) : null;
}
