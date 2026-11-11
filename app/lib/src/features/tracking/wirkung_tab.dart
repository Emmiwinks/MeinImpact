import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../feed/domain/opportunity_repository.dart';
import '../feed/presentation/widgets/app_colors.dart';
import '../feed/presentation/widgets/components/check_mark.dart';
import '../feed/presentation/widgets/components/surface_card.dart';
import '../feed/presentation/widgets/components/text_badges.dart';
import 'domain/action_log.dart';
import 'domain/impact_news.dart';

/// Opens a news link; replaceable in tests.
typedef LinkOpener = Future<void> Function(Uri url);

Future<void> _openInAppBrowser(Uri url) async {
  await launchUrl(url, mode: LaunchMode.inAppBrowserView);
}

/// "Wirkung" tab: every action the user marked done, newest first, each
/// with what Mein Impact found about it. The whole news feed is fetched and
/// matched here on the device, so the server never learns which actions
/// these are. Pull down to reload.
class WirkungTab extends StatefulWidget {
  const WirkungTab({
    required this.opportunityRepository,
    this.doneActions = const [],
    this.openLink = _openInAppBrowser,
    super.key,
  });

  final OpportunityRepository opportunityRepository;
  // The action log, oldest first.
  final List<ActionLogEntry> doneActions;
  final LinkOpener openLink;

  @override
  State<WirkungTab> createState() => _WirkungTabState();
}

class _WirkungTabState extends State<WirkungTab> {
  ImpactNewsFeed? _feed;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final feed = await widget.opportunityRepository.impactNews();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      // The actions still show; only their news is missing.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.doneActions.reversed.toList(growable: false);
    final feed = _feed ?? const ImpactNewsFeed();
    final withNews = actions.where((a) {
      final items = feed[a.opportunityId]?.items ?? const [];
      return items.any((i) => !i.isBackground);
    }).length;

    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
        children: [
          _Header(doneCount: actions.length, withNewsCount: withNews),
          const SizedBox(height: 18),
          if (actions.isEmpty)
            const _EmptyState()
          else ...[
            if (_failed) ...[
              const _LoadError(),
              const SizedBox(height: 12),
            ],
            SectionLabel(label: 'Deine Aktionen'),
            const SizedBox(height: 10),
            for (final action in actions) ...[
              _ActionCard(
                action: action,
                news: feed[action.opportunityId],
                loading: _loading,
                failed: _failed,
                openLink: widget.openLink,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.doneCount, required this.withNewsCount});

  final int doneCount;
  final int withNewsCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wirkung',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Was aus deinen Aktionen wird: Berichte und Stellungnahmen, '
            'die wir dazu finden.',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.mutedText,
              height: 1.3,
            ),
          ),
          if (doneCount > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    value: doneCount,
                    label: doneCount == 1
                        ? 'Aktion erledigt'
                        : 'Aktionen erledigt',
                    color: AppColors.greenWash,
                    textColor: AppColors.greenDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    value: withNewsCount,
                    label: 'mit Berichten',
                    color: AppColors.warmSurface,
                    textColor: AppColors.amberText,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.color,
    required this.textColor,
  });

  final int value;
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: textTheme.headlineMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: AppColors.surfaceMuted,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.flag_outlined, color: AppColors.mutedText),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Noch keine Aktion erledigt. Wenn du bei einer Aktion auf '
              '„Fertig“ tippst, verfolgen wir hier, was daraus wird.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mutedText,
                    height: 1.3,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Berichte konnten gerade nicht geladen werden. Zum Neuladen nach '
      'unten ziehen.',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.amberText,
          ),
    );
  }
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.action,
    required this.news,
    required this.loading,
    required this.failed,
    required this.openLink,
  });

  final ActionLogEntry action;
  // Null: not searched yet (or the feed did not load).
  final ImpactNewsEntry? news;
  final bool loading;
  final bool failed;
  final LinkOpener openLink;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  static const _collapsedCount = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final action = widget.action;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CheckMark(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${action.kind.label} · ${action.sourceOrg} · '
                      'erledigt am ${_formatDate(action.doneAt.toLocal())}',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._newsSection(context),
        ],
      ),
    );
  }

  List<Widget> _newsSection(BuildContext context) {
    final news = widget.news;
    if (news == null) {
      if (widget.loading) {
        return const [
          LinearProgressIndicator(
            minHeight: 2,
            color: AppColors.green,
            backgroundColor: Colors.transparent,
          ),
        ];
      }
      if (widget.failed) return const [];
      return [
        const _NewsNote(
          icon: Icons.search,
          text: 'Wir suchen bald nach Berichten dazu.',
        ),
      ];
    }
    if (news.items.isEmpty) {
      return [
        _NewsNote(
          icon: Icons.schedule,
          text: 'Noch keine Berichte gefunden (zuletzt gesucht am '
              '${_formatDate(news.checkedAt.toLocal())}). '
              'Wir schauen regelmäßig wieder nach.',
        ),
      ];
    }
    final items = news.items;
    final visible =
        _expanded ? items : items.take(_collapsedCount).toList(growable: false);
    return [
      if (items.every((i) => i.isBackground))
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: _NewsNote(
            icon: Icons.info_outline,
            text: 'Noch nichts direkt dazu. Hintergrund zum Thema:',
          ),
        ),
      for (final item in visible)
        _NewsTile(item: item, onTap: () => _open(item)),
      if (items.length > _collapsedCount)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.greenDark),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded
                  ? 'Weniger anzeigen'
                  : '${items.length - _collapsedCount} weitere anzeigen',
            ),
          ),
        ),
    ];
  }

  Future<void> _open(ImpactNewsItem item) async {
    final url = Uri.tryParse(item.url);
    if (url == null) return;
    await widget.openLink(url);
  }
}

class _NewsNote extends StatelessWidget {
  const _NewsNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.mutedText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedText,
                  height: 1.3,
                ),
          ),
        ),
      ],
    );
  }
}

class _NewsTile extends StatelessWidget {
  const _NewsTile({required this.item, required this.onTap});

  final ImpactNewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final host = Uri.tryParse(item.url)?.host.replaceFirst('www.', '') ?? '';
    final published = item.publishedOn;
    final meta = [
      if (host.isNotEmpty) host,
      if (published != null) _formatDate(published),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isStatement || item.isBackground)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Pill(
                      label: item.isStatement ? 'Stellungnahme' : 'Hintergrund',
                      color: item.isStatement
                          ? AppColors.blueText
                          : AppColors.mutedText,
                    ),
                  ),
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (item.snippet.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedText,
                      height: 1.3,
                    ),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.mutedText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: AppColors.mutedText,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';
