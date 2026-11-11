import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/mi_theme.dart';
import '../feed/domain/opportunity_repository.dart';
import '../feed/presentation/hand/hand_view.dart';
import '../feed/presentation/hand/topic_art.dart';
import 'data/starred_actions_store.dart';
import 'domain/action_log.dart';
import 'domain/impact_news.dart';

/// Opens a news link; replaceable in tests.
typedef LinkOpener = Future<void> Function(Uri url);

Future<void> _openInAppBrowser(Uri url) async {
  await launchUrl(url, mode: LaunchMode.inAppBrowserView);
}

/// "Wirkung" tab: the pile of played cards. Every action the user marked
/// done, newest first, each with what Mein Impact found about it. The whole
/// news feed is fetched and matched here on the device, so the server never
/// learns which actions these are. Pull down to reload.
class WirkungTab extends StatefulWidget {
  const WirkungTab({
    required this.opportunityRepository,
    this.doneActions = const [],
    this.openLink = _openInAppBrowser,
    this.starredStore = const StarredActionsStore(),
    super.key,
  });

  final OpportunityRepository opportunityRepository;
  // The action log, oldest first.
  final List<ActionLogEntry> doneActions;
  final LinkOpener openLink;
  final StarredActionsStore starredStore;

  @override
  State<WirkungTab> createState() => _WirkungTabState();
}

class _WirkungTabState extends State<WirkungTab> {
  ImpactNewsFeed? _feed;
  bool _loading = true;
  bool _failed = false;
  Set<String> _starred = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadStarred();
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

  Future<void> _loadStarred() async {
    final starred = await widget.starredStore.load();
    if (!mounted) return;
    setState(() => _starred = starred);
  }

  void _toggleStar(String opportunityId) {
    HapticFeedback.selectionClick();
    setState(() {
      _starred = {..._starred};
      if (!_starred.remove(opportunityId)) _starred.add(opportunityId);
    });
    widget.starredStore.save(_starred);
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.doneActions.reversed.toList(growable: false);
    if (actions.isEmpty) {
      return const HandMessage(
        title: 'Noch keine Aktion erledigt',
        body: 'Wenn du bei einer Aktion auf „Fertig“ tippst, landet sie '
            'hier, und wir verfolgen, was daraus wird.',
      );
    }

    final colors = context.mi;
    final feed = _feed ?? const ImpactNewsFeed();
    final withNews = actions.where((a) {
      final items = feed[a.opportunityId]?.items ?? const [];
      return items.any((i) => !i.isBackground);
    }).length;

    return RefreshIndicator(
      color: colors.onCard,
      backgroundColor: colors.cardStock,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: MiSpace.lg, bottom: MiSpace.xl),
        children: [
          _Header(actions: actions, withNewsCount: withNews),
          if (_failed) const _LoadError(),
          const SizedBox(height: MiSpace.lg),
          for (final action in actions)
            _ActionRow(
              action: action,
              news: feed[action.opportunityId],
              loading: _loading,
              failed: _failed,
              starred: _starred.contains(action.opportunityId),
              onStar: () => _toggleStar(action.opportunityId),
              openLink: widget.openLink,
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.actions, required this.withNewsCount});

  // Newest first.
  final List<ActionLogEntry> actions;
  final int withNewsCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final count = actions.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MiSpace.lg),
      child: Row(
        children: [
          _PlayedPile(actions: actions),
          const SizedBox(width: MiSpace.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1 ? '1 Aktion erledigt' : '$count Aktionen erledigt',
                  style: text.titleLarge,
                ),
                const SizedBox(height: MiSpace.xs),
                Text(
                  withNewsCount == 0
                      ? 'Noch keine Berichte dazu'
                      : '$withNewsCount davon mit Berichten',
                  style: text.bodyLarge?.copyWith(
                    color: colors.onTableMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The last few played cards, face up on a small pile: where a card lands
/// when it is played in the hand.
class _PlayedPile extends StatelessWidget {
  const _PlayedPile({required this.actions});

  // Newest first.
  final List<ActionLogEntry> actions;

  // Newest upright, the ones below fanned out like a tossed pile.
  static const _angles = [0.0, 0.26, -0.22];
  static const _shifts = [0.0, 8.0, -7.0];

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final top = actions.take(_angles.length).toList(growable: false);
    return ExcludeSemantics(
      child: SizedBox(
        width: 84,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Oldest at the bottom, the newest card on top and upright.
            for (var i = top.length - 1; i >= 0; i--)
              Transform.translate(
                offset: Offset(_shifts[i], 0),
                child: Transform.rotate(
                  angle: _angles[i],
                  child: Container(
                    width: 50,
                    height: 68,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: colors.cardStock,
                      borderRadius: BorderRadius.circular(MiRadius.tile - 3),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow,
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(MiRadius.tile - 6),
                      child: TopicArt(
                        look: TopicLook.forTags(
                          top[i].affectedTags,
                          top[i].kind,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MiSpace.lg,
        MiSpace.base,
        MiSpace.lg,
        0,
      ),
      child: _Note(
        icon: Icons.cloud_off_outlined,
        text: 'Berichte konnten gerade nicht geladen werden. Zum Neuladen '
            'nach unten ziehen.',
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.action,
    required this.news,
    required this.loading,
    required this.failed,
    required this.starred,
    required this.onStar,
    required this.openLink,
  });

  final ActionLogEntry action;
  // Null: not searched yet (or the feed did not load).
  final ImpactNewsEntry? news;
  final bool loading;
  final bool failed;
  final bool starred;
  final VoidCallback onStar;
  final LinkOpener openLink;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  static const _collapsedCount = 2;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final action = widget.action;
    final news = _newsSection(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        MiSpace.lg,
        MiSpace.lg,
        MiSpace.sm,
        MiSpace.lg,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.keyline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardThumbnail(
                look: TopicLook.forTags(action.affectedTags, action.kind),
              ),
              const SizedBox(width: MiSpace.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.title, style: text.titleMedium),
                    const SizedBox(height: MiSpace.sm),
                    Text(
                      '${action.kind.label} · ${action.sourceOrg} · '
                      'erledigt am ${_formatDate(action.doneAt.toLocal())}',
                      style: text.labelMedium?.copyWith(
                        color: colors.onTableMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Pulled up so the star lines up with the title.
              Transform.translate(
                offset: const Offset(0, -MiSpace.md),
                child: _StarButton(
                  starred: widget.starred,
                  onPressed: widget.onStar,
                ),
              ),
            ],
          ),
          if (news.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: MiSpace.md,
                right: MiSpace.lg - MiSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: news,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _newsSection(BuildContext context) {
    final colors = context.mi;
    final news = widget.news;
    if (news == null) {
      if (widget.loading) {
        return [
          Semantics(
            label: 'Berichte werden geladen',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MiRadius.chip),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: colors.onTableMuted,
                backgroundColor: colors.keyline,
              ),
            ),
          ),
        ];
      }
      if (widget.failed) return const [];
      return const [
        _Note(
          icon: Icons.search,
          text: 'Wir suchen bald nach Berichten dazu.',
        ),
      ];
    }
    if (news.items.isEmpty) {
      return [
        _Note(
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
          padding: EdgeInsets.only(bottom: MiSpace.sm),
          child: _Note(
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
            // Label in line with the text inside the tiles above.
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: MiSpace.base),
            ),
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

/// Follow an action: the user wants to hear when something new turns up
/// about it. Marked like the selected destination in the navigation bar:
/// an amber pill with an ink star, the interface's one "selected" accent.
class _StarButton extends StatelessWidget {
  const _StarButton({required this.starred, required this.onPressed});

  final bool starred;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final reduced = MiMotion.reduced(context);
    return IconButton(
      onPressed: onPressed,
      isSelected: starred,
      tooltip: starred ? 'Nicht mehr folgen' : 'Folgen',
      style: IconButton.styleFrom(
        backgroundColor: starred ? colors.topics[2] : Colors.transparent,
        foregroundColor: starred ? colors.onCard : colors.onTableMuted,
        // A 40dp disc; the padded tap target keeps 48dp to hit.
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: AnimatedSwitcher(
        duration: reduced ? Duration.zero : MiMotion.quick,
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          starred ? Icons.star_rounded : Icons.star_outline_rounded,
          key: ValueKey(starred),
          size: 24,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 18, color: colors.onTableMuted),
        ),
        const SizedBox(width: MiSpace.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.onTableMuted),
          ),
        ),
      ],
    );
  }
}

/// One report, flat on the table: only cards cast shadows.
class _NewsTile extends StatelessWidget {
  const _NewsTile({required this.item, required this.onTap});

  final ImpactNewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final host = Uri.tryParse(item.url)?.host.replaceFirst('www.', '') ?? '';
    final published = item.publishedOn;
    final meta = [
      if (host.isNotEmpty) host,
      if (published != null) _formatDate(published),
    ].join(' · ');
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MiRadius.tile),
      side: BorderSide(color: colors.keyline),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: MiSpace.sm),
      child: Material(
        color: colors.tableRaised,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              MiSpace.base,
              MiSpace.md,
              MiSpace.base,
              MiSpace.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isStatement || item.isBackground)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MiSpace.sm),
                    child: _KindChip(
                      item.isStatement ? 'Stellungnahme' : 'Hintergrund',
                    ),
                  ),
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge,
                ),
                if (item.snippet.isNotEmpty) ...[
                  const SizedBox(height: MiSpace.xs),
                  Text(
                    item.snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onTableMuted,
                    ),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: MiSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(
                            color: colors.onTableMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: MiSpace.sm),
                      Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: colors.onTableMuted,
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

/// What kind of report this is, as an outlined pill like the card back's
/// fact chips: information, not a colour-coded verdict.
class _KindChip extends StatelessWidget {
  const _KindChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MiRadius.chip),
        border: Border.all(color: colors.onTableMuted),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';
