/// What Mein Impact found about one tracked opportunity: news articles and
/// statements, judged relevant on the server.
class ImpactNewsItem {
  const ImpactNewsItem({
    required this.level,
    required this.kind,
    required this.title,
    required this.url,
    required this.snippet,
    this.publishedOn,
  });

  factory ImpactNewsItem.fromJson(Map<String, Object?> json) {
    final publishedOn = json['published_on'] as String?;
    return ImpactNewsItem(
      level: json['level'] as String? ?? 'exact',
      kind: json['kind'] as String? ?? 'news',
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      publishedOn: publishedOn != null ? DateTime.tryParse(publishedOn) : null,
    );
  }

  // "exact"/"issue": about the action's concrete matter; "background": the
  // overarching topic only.
  final String level;
  // "news" or "statement" (also "social", "other").
  final String kind;
  final String title;
  final String url;
  final String snippet;
  final DateTime? publishedOn;

  bool get isBackground => level == 'background';

  bool get isStatement => kind == 'statement';
}

/// One searched opportunity. Empty [items]: searched, nothing found yet.
class ImpactNewsEntry {
  const ImpactNewsEntry({required this.checkedAt, this.items = const []});

  factory ImpactNewsEntry.fromJson(Map<String, Object?> json) {
    return ImpactNewsEntry(
      checkedAt: DateTime.parse(json['checked_at'] as String),
      items: [
        for (final item in json['items'] as List<Object?>? ?? const [])
          if (item is Map<String, Object?>) ImpactNewsItem.fromJson(item),
      ],
    );
  }

  final DateTime checkedAt;
  final List<ImpactNewsItem> items;
}

/// The news on every tracked opportunity, for everyone. The app picks its
/// own actions from it, so the server never learns which ones they are.
class ImpactNewsFeed {
  const ImpactNewsFeed([this.entries = const {}]);

  factory ImpactNewsFeed.fromJson(Map<String, Object?> json) {
    return ImpactNewsFeed({
      for (final raw in json['opportunities'] as List<Object?>? ?? const [])
        if (raw is Map<String, Object?>)
          raw['opportunity_id'] as String: ImpactNewsEntry.fromJson(raw),
    });
  }

  // By opportunity id. Missing: not searched yet.
  final Map<String, ImpactNewsEntry> entries;

  ImpactNewsEntry? operator [](String opportunityId) => entries[opportunityId];
}
