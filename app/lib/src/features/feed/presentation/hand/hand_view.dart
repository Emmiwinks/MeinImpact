import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../data/opportunity_relevance_ranker.dart';
import '../../domain/opportunity.dart';
import 'action_card.dart';
import 'all_actions_screen.dart';

/// How many of the best matches make up the hand.
const kHandSize = 5;

/// The "Für dich" tab: the user's best matches as a fanned hand of cards,
/// best first. Playing a card hands it to [onPlay]; when that reports the
/// action done, the card flies onto the Wirkung pile and [onPlayed] takes
/// it out, so the next best match moves up. Everything else is one tap away
/// in "Alle ansehen", where any card can be taken into the hand.
class HandView extends StatefulWidget {
  const HandView({
    required this.opportunities,
    required this.actionLabel,
    required this.onPlay,
    required this.onPlayed,
    this.onOpened,
    super.key,
  });

  // Ranked, best first, without the ones already done.
  final List<RankedOpportunity> opportunities;
  final String Function(Opportunity opportunity) actionLabel;
  // Opens the action; resolves to true when the user marked it done.
  final Future<bool> Function(RankedOpportunity ranked) onPlay;
  final void Function(RankedOpportunity ranked) onPlayed;
  final void Function(RankedOpportunity ranked)? onOpened;

  @override
  State<HandView> createState() => _HandViewState();
}

class _HandViewState extends State<HandView>
    with SingleTickerProviderStateMixin {
  final _fanKey = GlobalKey<_CardFanState>();
  final _frontKey = GlobalKey();
  // Fractional index of the front card, shared by the fan and the dots.
  final _position = ValueNotifier<double>(0);
  // Cards taken into the hand from "Alle ansehen", most recent first.
  final _pulled = <String>[];
  late final AnimationController _flight;

  @override
  void initState() {
    super.initState();
    _flight = AnimationController(vsync: this, duration: MiMotion.flight);
  }

  @override
  void dispose() {
    _flight.dispose();
    _position.dispose();
    super.dispose();
  }

  List<RankedOpportunity> get _hand {
    final byId = {for (final r in widget.opportunities) r.opportunity.id: r};
    final pulled = [
      for (final id in _pulled)
        if (byId[id] case final r?) r,
    ];
    final rest = widget.opportunities
        .where((r) => !_pulled.contains(r.opportunity.id))
        .take(kHandSize);
    return [...pulled, ...rest];
  }

  Future<void> _play(RankedOpportunity ranked) async {
    final done = await widget.onPlay(ranked);
    if (!done || !mounted) return;
    if (!MiMotion.reduced(context)) await _fly(ranked);
    if (!mounted) return;
    _pulled.remove(ranked.opportunity.id);
    widget.onPlayed(ranked);
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Erledigt. Die Karte liegt jetzt bei deiner Wirkung.',
      TextDirection.ltr,
    );
  }

  // The played card shrinks onto the Wirkung tab, the last of the three
  // navigation destinations.
  Future<void> _fly(RankedOpportunity ranked) async {
    final box = _frontKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final start = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final target = Offset(screen.width * 5 / 6, screen.height - bottom - 44);
    final theme = Theme.of(context);
    final entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: _flight,
        builder: (_, child) {
          final t = Curves.easeInCubic.transform(_flight.value);
          final center = Offset.lerp(start.center, target, t)!;
          return Positioned(
            left: center.dx - start.width / 2,
            top: center.dy - start.height / 2,
            width: start.width,
            height: start.height,
            child: IgnorePointer(
              child: Opacity(
                opacity: (1 - max(0.0, t - 0.75) * 4).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: 0.35 * t,
                  child: Transform.scale(scale: 1 - 0.88 * t, child: child),
                ),
              ),
            ),
          );
        },
        child: Theme(
          data: theme,
          child: ActionCard(
            ranked: ranked,
            actionLabel: widget.actionLabel(ranked.opportunity),
            isFront: false,
          ),
        ),
      ),
    );
    HapticFeedback.mediumImpact();
    Overlay.of(context, rootOverlay: true).insert(entry);
    _fanKey.currentState?.hideFront = true;
    try {
      await _flight.forward(from: 0);
    } finally {
      entry.remove();
      _fanKey.currentState?.hideFront = false;
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _showAll() async {
    final theme = Theme.of(context);
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: theme,
          child: AllActionsScreen(opportunities: widget.opportunities),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pulled
        ..remove(picked)
        ..insert(0, picked);
    });
    _fanKey.currentState?.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final hand = _hand;
    final total = widget.opportunities.length;
    // No header: the tab already says "Für dich" and the dots count the
    // cards, so the space goes to the cards.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: MiSpace.base),
        Expanded(
          child: _CardFan(
            key: _fanKey,
            cards: hand,
            position: _position,
            frontKey: _frontKey,
            builder: (ranked, {required isFront, required contentOpacity}) =>
                ActionCard(
              ranked: ranked,
              actionLabel: widget.actionLabel(ranked.opportunity),
              isFront: isFront,
              contentOpacity: contentOpacity,
              onAction: isFront ? () => _play(ranked) : null,
              onOpened: () => widget.onOpened?.call(ranked),
            ),
            endCard: ({required isFront, required contentOpacity}) => _EndCard(
              dealt: hand.length,
              total: total,
              contentOpacity: contentOpacity,
              onShowAll: _showAll,
              onRestart: () => _fanKey.currentState?.animateTo(0),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MiSpace.lg,
            0,
            MiSpace.base,
            MiSpace.sm,
          ),
          child: ValueListenableBuilder(
            valueListenable: _position,
            builder: (context, position, _) => Row(
              children: [
                _Dots(count: hand.length + 1, position: position),
                const Spacer(),
                // The closing card carries its own "Alle ansehen".
                if (total > 1 && position.round() < hand.length)
                  TextButton(
                    onPressed: _showAll,
                    child: Text('Alle $total ansehen'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

typedef _CardBuilder = Widget Function(
  RankedOpportunity ranked, {
  required bool isFront,
  required double contentOpacity,
});

typedef _EndBuilder = Widget Function({
  required bool isFront,
  required double contentOpacity,
});

/// The fanned cards: the front one upright, the next ones peeking out to
/// the right behind it, and a closing card after the last one, so the hand
/// has an end. A horizontal swipe moves through it and snaps to a card.
class _CardFan extends StatefulWidget {
  const _CardFan({
    required this.cards,
    required this.position,
    required this.frontKey,
    required this.builder,
    required this.endCard,
    super.key,
  });

  final List<RankedOpportunity> cards;
  final ValueNotifier<double> position;
  final GlobalKey frontKey;
  final _CardBuilder builder;
  final _EndBuilder endCard;

  @override
  State<_CardFan> createState() => _CardFanState();
}

class _CardFanState extends State<_CardFan>
    with SingleTickerProviderStateMixin {
  ValueNotifier<double> get position => widget.position;
  late final AnimationController _snap;
  double _cardWidth = 300;
  bool _hideFront = false;

  set hideFront(bool value) => setState(() => _hideFront = value);

  // The closing card sits right after the last action card.
  int get _last => widget.cards.length;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController.unbounded(vsync: this)
      ..addListener(() => position.value = _snap.value);
    position.addListener(_onMove);
  }

  @override
  void didUpdateWidget(_CardFan old) {
    super.didUpdateWidget(old);
    if (position.value > _last) {
      _snap.stop();
      position.value = _last.toDouble();
    }
  }

  @override
  void dispose() {
    position.removeListener(_onMove);
    _snap.dispose();
    super.dispose();
  }

  void _onMove() => setState(() {});

  void jumpTo(int index) {
    _snap.stop();
    position.value = index.clamp(0, _last).toDouble();
  }

  void animateTo(int index) {
    final target = index.clamp(0, _last).toDouble();
    if (MiMotion.reduced(context)) {
      jumpTo(target.toInt());
      return;
    }
    _snap.value = position.value;
    _snap.animateTo(target, duration: MiMotion.settle, curve: MiMotion.ease);
  }

  void _onDrag(DragUpdateDetails details) {
    _snap.stop();
    position.value = (position.value - details.delta.dx / (_cardWidth * 0.9))
        .clamp(-0.3, _last + 0.3);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final fling = velocity.abs() > 300 ? -velocity.sign * 0.5 : 0.0;
    animateTo((position.value + fling).round());
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    return LayoutBuilder(
      builder: (context, constraints) {
        _cardWidth = min(constraints.maxWidth - 2 * (MiSpace.lg + 20), 340);
        // As tall as the table allows, up to a playing card's proportions.
        final cardHeight =
            min(constraints.maxHeight - MiSpace.lg, _cardWidth * 1.75);
        final pos = position.value;
        final front = pos.round().clamp(0, _last);
        final visible = [
          for (var i = 0; i <= _last; i++)
            if (i - pos > -1.2 && i - pos < 3.2) i,
        ]..sort((a, b) {
            // Furthest behind first; a card leaving to the left on top.
            final da = a - pos, db = b - pos;
            if (da < 0 != db < 0) return da < 0 ? 1 : -1;
            return db.compareTo(da);
          });
        return Semantics(
          container: true,
          label: front < cards.length
              ? 'Karte ${front + 1} von ${cards.length}'
              : 'Ende deiner Hand',
          onIncrease: front < _last ? () => animateTo(front + 1) : null,
          onDecrease: front > 0 ? () => animateTo(front - 1) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _onDrag,
            onHorizontalDragEnd: _onDragEnd,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final i in visible)
                  _placed(
                    i < cards.length
                        ? ValueKey(cards[i].opportunity.id)
                        : const ValueKey('end'),
                    (contentOpacity) => i < cards.length
                        ? widget.builder(
                            cards[i],
                            isFront: i == front,
                            contentOpacity: contentOpacity,
                          )
                        : widget.endCard(
                            isFront: i == front,
                            contentOpacity: contentOpacity,
                          ),
                    delta: i - pos,
                    isFront: i == front,
                    width: _cardWidth,
                    height: cardHeight,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _placed(
    Key key,
    Widget Function(double contentOpacity) build, {
    required double delta,
    required bool isFront,
    required double width,
    required double height,
  }) {
    final behind = max(0.0, delta);
    final leaving = min(0.0, delta);
    final dx = behind * 22 + leaving * (width + 60);
    final angle = behind * 0.07 - leaving * 0.12;
    final scale = 1 - 0.035 * behind;
    final card = SizedBox(
      key: isFront ? widget.frontKey : null,
      width: width,
      height: height,
      child: build((1 - behind * 2).clamp(0.0, 1.0)),
    );
    return Transform.translate(
      key: key,
      offset: Offset(dx, behind * 6),
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.bottomCenter,
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: isFront && _hideFront ? 0 : 1,
            child: IgnorePointer(ignoring: !isFront, child: card),
          ),
        ),
      ),
    );
  }
}

/// The card after the last one: the hand is done. It points on to
/// everything else, or back to the first card.
class _EndCard extends StatelessWidget {
  const _EndCard({
    required this.dealt,
    required this.total,
    required this.contentOpacity,
    required this.onShowAll,
    required this.onRestart,
  });

  final int dealt;
  final int total;
  final double contentOpacity;
  final VoidCallback onShowAll;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final more = total > dealt;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MiRadius.card),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Material(
        color: colors.cardStock,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MiRadius.card),
          side: BorderSide(color: colors.keyline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Opacity(
          opacity: contentOpacity,
          child: Padding(
            padding: const EdgeInsets.all(MiSpace.lg),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // Only where it fits next to the words.
                            if (constraints.maxHeight > 440) ...[
                              const _FaceDownCards(),
                              const SizedBox(height: MiSpace.lg),
                            ],
                            Text(
                              dealt == 1
                                  ? 'Das war deine Karte.'
                                  : 'Das war deine $dealt.',
                              textAlign: TextAlign.center,
                              style: text.titleLarge
                                  ?.copyWith(color: colors.onCard),
                            ),
                            if (!more) ...[
                              const SizedBox(height: MiSpace.sm),
                              Text(
                                'Mehr gibt es gerade nicht. Neue Aktionen '
                                'kommen dazu, sobald sie veröffentlicht werden.',
                                textAlign: TextAlign.center,
                                style: text.bodyMedium
                                    ?.copyWith(color: colors.onCardMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: MiSpace.base),
                  if (more) ...[
                    FilledButton(
                      onPressed: onShowAll,
                      child: Text('Alle $total ansehen'),
                    ),
                    const SizedBox(height: MiSpace.xs),
                  ],
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: colors.onCard),
                    onPressed: onRestart,
                    child: const Text('Zurück zur ersten Karte'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.position});

  final int count;
  final double position;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: MiMotion.quick,
              margin: const EdgeInsets.only(right: 6),
              width: i == position.round() ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == position.round()
                    ? colors.onTable
                    : colors.onTable.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

/// A short message on the table instead of the hand: nothing to deal, still
/// dealing, or the cards could not be fetched.
class HandMessage extends StatelessWidget {
  const HandMessage({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MiSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FaceDownCards(),
            const SizedBox(height: MiSpace.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
            const SizedBox(height: MiSpace.sm),
            Text(
              body,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: MiSpace.lg),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.onTable,
                  foregroundColor: colors.table,
                  minimumSize: const Size(200, 52),
                ),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// While the hand is being fetched: the deck, face down.
class HandLoading extends StatelessWidget {
  const HandLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Semantics(
      label: 'Deine Karten werden geladen',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FaceDownCards(),
            const SizedBox(height: MiSpace.lg),
            Text(
              'Deine Karten werden gemischt …',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onTableMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceDownCards extends StatelessWidget {
  const _FaceDownCards();

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    Widget back(double angle, Color color) => Transform.rotate(
          angle: angle,
          child: Container(
            width: 92,
            height: 132,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(MiRadius.tile),
              border: Border.all(color: colors.cardStock, width: 4),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
        );
    return ExcludeSemantics(
      child: SizedBox(
        width: 180,
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            back(-0.22, colors.topics[1]),
            back(0.2, colors.topics[3]),
            back(0, colors.topics[0]),
          ],
        ),
      ),
    );
  }
}
