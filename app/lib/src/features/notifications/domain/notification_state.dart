import '../../tracking/domain/action_log.dart';

/// The Android channels: what users switch on and off in the system's
/// notification settings for the app (the app has no switches of its own).
enum NotificationChannel {
  news(
    'news',
    'Neuigkeiten & Ergebnisse',
    'Neues zu Aktionen mit Stern, Ergebnisse, Abstimmungen',
  ),
  flame('flame', 'Flamme', 'Kurz bevor deine Flamme ausgeht'),
  week('week', 'Neue Woche', 'Montags, wenn Neues zu dir passt'),
  reminders(
    'reminders',
    'Erinnerungen',
    'Wenn eine Aktion, die du dir angesehen hast, bald endet',
  );

  const NotificationChannel(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;
}

/// The kinds of notification, most important first: when two want the
/// same day, the earlier one wins.
enum NotificationKind {
  // A petition the user signed reached its goal.
  result('result', NotificationChannel.news),
  // A council vote the user wrote about is tomorrow.
  decision('decision', NotificationChannel.news),
  // New reports on a starred action.
  news('news', NotificationChannel.news),
  // The streak's flame goes out tonight.
  flame('flame', NotificationChannel.flame),
  // A card the user looked at closes soon.
  deadline('deadline', NotificationChannel.reminders),
  // Monday: new opportunities that fit.
  week('week', NotificationChannel.week),
  // The user left an action's site without "Fertig".
  tookPart('took_part', NotificationChannel.reminders);

  const NotificationKind(this.wire, this.channel);

  final String wire;
  final NotificationChannel channel;

  /// Results always come; they don't count towards the limits.
  bool get exempt => this == result;

  /// The kind a key was made for (see [PlannedNotification.key]).
  static NotificationKind? ofKey(String key) {
    final wire = key.split(':').first;
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

/// One notification, shown now or scheduled for [at].
class PlannedNotification {
  const PlannedNotification({
    required this.key,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
    this.opportunityId,
  });

  factory PlannedNotification.fromJson(Map<String, Object?> json) {
    return PlannedNotification(
      key: json['key'] as String,
      kind: NotificationKind.ofKey(json['key'] as String) ??
          NotificationKind.news,
      at: DateTime.parse(json['at'] as String).toLocal(),
      title: json['title'] as String,
      body: json['body'] as String,
      opportunityId: json['opportunity_id'] as String?,
    );
  }

  /// `kind:what`, e.g. "flame:2026-11-16": one notification per key, ever.
  final String key;
  final NotificationKind kind;
  final DateTime at;
  final String title;
  final String body;
  // The action a tap opens; null for a bundle or none.
  final String? opportunityId;

  /// The system's id for it: the same key always gets the same id, so
  /// showing it twice replaces it instead of stacking up.
  int get id {
    // FNV-1a, kept to 31 bits.
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  Map<String, Object?> toJson() => {
        'key': key,
        'at': at.toUtc().toIso8601String(),
        'title': title,
        'body': body,
        'opportunity_id': opportunityId,
      };
}

/// A card the user turned over or whose site they opened without marking
/// it done: what deadline and "did you take part?" reminders are about.
class LookedAtCard {
  const LookedAtCard({
    required this.card,
    required this.at,
    this.openedSite = false,
  });

  factory LookedAtCard.fromJson(Map<String, Object?> json) {
    return LookedAtCard(
      card: ActionLogEntry.fromJson(json['card'] as Map<String, Object?>),
      at: DateTime.parse(json['at'] as String).toLocal(),
      openedSite: json['opened_site'] as bool? ?? false,
    );
  }

  // The card as it would go into the action log.
  final ActionLogEntry card;
  final DateTime at;
  final bool openedSite;

  Map<String, Object?> toJson() => {
        'card': card.toJson(),
        'at': at.toUtc().toIso8601String(),
        'opened_site': openedSite,
      };
}

/// Everything notifications remember, on the device only.
class NotificationState {
  const NotificationState({
    this.shown = const {},
    this.planned = const [],
    this.week,
    this.newsSeen = const {},
    this.lookedAt = const {},
    this.lastOpenedAt,
    this.poolFetchedAt,
  });

  factory NotificationState.fromJson(Map<String, Object?> json) {
    final shown = json['shown'] as Map<String, Object?>? ?? const {};
    final newsSeen = json['news_seen'] as Map<String, Object?>? ?? const {};
    final lookedAt = json['looked_at'] as Map<String, Object?>? ?? const {};
    return NotificationState(
      shown: shown
          .map((k, v) => MapEntry(k, DateTime.parse(v as String).toLocal())),
      planned: [
        for (final raw in json['planned'] as List<Object?>? ?? const [])
          PlannedNotification.fromJson(raw as Map<String, Object?>),
      ],
      week: json['week'] is Map<String, Object?>
          ? PlannedNotification.fromJson(json['week'] as Map<String, Object?>)
          : null,
      newsSeen: newsSeen.map(
        (k, v) => MapEntry(k, (v as List<Object?>).cast<String>().toSet()),
      ),
      lookedAt: lookedAt.map(
        (k, v) => MapEntry(k, LookedAtCard.fromJson(v as Map<String, Object?>)),
      ),
      lastOpenedAt: _date(json['last_opened_at']),
      poolFetchedAt: _date(json['pool_fetched_at']),
    );
  }

  // Key -> when it was shown (or fired as scheduled).
  final Map<String, DateTime> shown;
  // Scheduled with the system and not yet due.
  final List<PlannedNotification> planned;
  // The next Monday's notification as last worked out from the pool, which
  // is not loaded on every check.
  final PlannedNotification? week;
  // Starred action -> report URLs already known. Missing: starred since the
  // last check, so what is there now counts as known.
  final Map<String, Set<String>> newsSeen;
  // By opportunity id.
  final Map<String, LookedAtCard> lookedAt;
  final DateTime? lastOpenedAt;
  // The pool is big, so the background check loads it only now and then.
  final DateTime? poolFetchedAt;

  NotificationState copyWith({
    Map<String, DateTime>? shown,
    List<PlannedNotification>? planned,
    Map<String, Set<String>>? newsSeen,
    Map<String, LookedAtCard>? lookedAt,
    DateTime? lastOpenedAt,
    DateTime? poolFetchedAt,
  }) {
    return NotificationState(
      shown: shown ?? this.shown,
      planned: planned ?? this.planned,
      week: week,
      newsSeen: newsSeen ?? this.newsSeen,
      lookedAt: lookedAt ?? this.lookedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      poolFetchedAt: poolFetchedAt ?? this.poolFetchedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'shown': shown.map((k, v) => MapEntry(k, v.toUtc().toIso8601String())),
        'planned': [for (final p in planned) p.toJson()],
        'week': week?.toJson(),
        'news_seen': newsSeen.map((k, v) => MapEntry(k, v.toList())),
        'looked_at': lookedAt.map((k, v) => MapEntry(k, v.toJson())),
        'last_opened_at': lastOpenedAt?.toUtc().toIso8601String(),
        'pool_fetched_at': poolFetchedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.parse(value).toLocal() : null;
}
