import '../../feed/domain/opportunity.dart';

/// How an action was marked done.
enum ActionVia {
  // "Fertig" in the in-app browser (Android/iOS).
  inAppBrowser('in_app_browser'),
  // "Fertig" after the letter pop-up for a council decision.
  letter('letter');

  const ActionVia(this.wire);

  final String wire;

  static ActionVia fromWire(String? value) => values.firstWhere(
        (via) => via.wire == value,
        orElse: () => ActionVia.inAppBrowser,
      );
}

/// One action the user marked done. Self-reported, stored on the device
/// only. Carries a snapshot of the opportunity because the pool holds only
/// the latest run, and Mein Impact must still show actions that left it.
class ActionLogEntry {
  const ActionLogEntry({
    required this.opportunityId,
    required this.doneAt,
    required this.via,
    required this.title,
    required this.kind,
    required this.sourceOrg,
    required this.sourceUrl,
    this.closesOn,
    this.affectedTags = const [],
    this.lebenslagen,
    this.supportCount,
    this.supportGoal,
  });

  factory ActionLogEntry.fromOpportunity(
    Opportunity opportunity, {
    required DateTime doneAt,
    required ActionVia via,
  }) {
    return ActionLogEntry(
      opportunityId: opportunity.id,
      doneAt: doneAt.toUtc(),
      via: via,
      title: opportunity.title,
      kind: opportunity.kind,
      sourceOrg: opportunity.sourceOrg,
      sourceUrl: opportunity.sourceUrl,
      closesOn: opportunity.closesOn,
      affectedTags: opportunity.affectedTags,
      lebenslagen: opportunity.lebenslagen,
      supportCount: opportunity.supportCount,
      supportGoal: opportunity.supportGoal,
    );
  }

  factory ActionLogEntry.fromJson(Map<String, Object?> json) {
    final snapshot = json['snapshot'] as Map<String, Object?>;
    final closesOn = snapshot['closes_on'] as String?;
    return ActionLogEntry(
      opportunityId: json['opportunity_id'] as String,
      doneAt: DateTime.parse(json['done_at'] as String),
      via: ActionVia.fromWire(json['via'] as String?),
      title: snapshot['title'] as String,
      kind: OpportunityKind.fromWire(snapshot['kind'] as String?),
      sourceOrg: snapshot['source_org'] as String,
      sourceUrl: snapshot['source_url'] as String,
      closesOn: closesOn != null ? DateTime.parse(closesOn) : null,
      affectedTags:
          (snapshot['affected_tags'] as List<Object?>?)?.cast<String>() ??
              const [],
      lebenslagen: (snapshot['lebenslagen'] as List<Object?>?)?.cast<String>(),
      supportCount: snapshot['support_count'] as int?,
      supportGoal: snapshot['support_goal'] as int?,
    );
  }

  final String opportunityId;
  final DateTime doneAt;
  final ActionVia via;
  final String title;
  final OpportunityKind kind;
  final String sourceOrg;
  final String sourceUrl;
  final DateTime? closesOn;
  final List<String> affectedTags;
  // Null in entries saved before they were kept: unknown, so notifications
  // look in the pool and otherwise treat the action as private.
  final List<String>? lebenslagen;
  // Signatures and goal when it was done, so a goal reached later is news.
  final int? supportCount;
  final int? supportGoal;

  /// The same action, done at [at] (a card looked at earlier, then reported
  /// done from a notification).
  ActionLogEntry withDoneAt(DateTime at) => ActionLogEntry(
        opportunityId: opportunityId,
        doneAt: at.toUtc(),
        via: via,
        title: title,
        kind: kind,
        sourceOrg: sourceOrg,
        sourceUrl: sourceUrl,
        closesOn: closesOn,
        affectedTags: affectedTags,
        lebenslagen: lebenslagen,
        supportCount: supportCount,
        supportGoal: supportGoal,
      );

  Map<String, Object?> toJson() {
    final closes = closesOn;
    return {
      'opportunity_id': opportunityId,
      'done_at': doneAt.toUtc().toIso8601String(),
      'via': via.wire,
      'snapshot': {
        'title': title,
        'kind': kind.wire,
        'source_org': sourceOrg,
        'source_url': sourceUrl,
        'closes_on': closes != null
            ? '${closes.year.toString().padLeft(4, '0')}-'
                '${closes.month.toString().padLeft(2, '0')}-'
                '${closes.day.toString().padLeft(2, '0')}'
            : null,
        'affected_tags': affectedTags,
        'lebenslagen': lebenslagen,
        'support_count': supportCount,
        'support_goal': supportGoal,
      },
    };
  }
}

/// Every action the user marked done, at most one entry per opportunity.
class ActionLog {
  const ActionLog([this.entries = const []]);

  factory ActionLog.fromJson(Map<String, Object?> json) {
    final raw = json['entries'] as List<Object?>? ?? const [];
    return ActionLog([
      for (final entry in raw)
        ActionLogEntry.fromJson(entry as Map<String, Object?>),
    ]);
  }

  static const _version = 1;

  // Oldest first.
  final List<ActionLogEntry> entries;

  Set<String> get doneIds => {for (final e in entries) e.opportunityId};

  bool isDone(String opportunityId) =>
      entries.any((e) => e.opportunityId == opportunityId);

  /// Adds [entry]; marking an action done twice keeps the first entry.
  ActionLog withDone(ActionLogEntry entry) {
    if (isDone(entry.opportunityId)) return this;
    return ActionLog([...entries, entry]);
  }

  Map<String, Object?> toJson() => {
        'version': _version,
        'entries': [for (final e in entries) e.toJson()],
      };
}
