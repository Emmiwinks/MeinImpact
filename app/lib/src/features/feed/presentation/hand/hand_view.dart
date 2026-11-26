import 'dart:math';

import 'package:flutter/foundation.dart';
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
/// it out, so the next best match moves up. A long press lifts a card, and
/// dropped on the trash can it is thrown away ([onThrow]); the next best
/// match moves up too. Everything else
/// is one tap away in "Alle ansehen", where any card can be taken into the
/// hand.
class HandView extends StatefulWidget {
  const HandView({
    required this.opportunities,
    required this.actionLabel,
    required this.onPlay,
    required this.onPlayed,
    this.onOpened,
    this.onThrow,
    this.throwHint = false,
    this.turnHint = false,
    this.onTurnHinted,
    this.doneIds = const {},
    super.key,
  });

  // Ranked, best first, without the ones already done (a bundle stays
  // while any of its options is open).
  final List<RankedOpportunity> opportunities;
  // Done opportunity ids: a bundle's done options show as done.
  final Set<String> doneIds;
  final String Function(Opportunity opportunity) actionLabel;
  // Opens the action; resolves to true when the user marked it done.
  final Future<bool> Function(RankedOpportunity ranked) onPlay;
  final void Function(RankedOpportunity ranked) onPlayed;
  final void Function(RankedOpportunity ranked)? onOpened;
  // A card was dropped in the trash at [position] (0 = first); resolves to
  // false when the user kept it after all, and it comes back.
  final Future<bool> Function(RankedOpportunity ranked, int position)? onThrow;
  // Shows once, for someone who never threw a card away, that a long press
  // lifts a card: the front card rises once and a line says so.
  final bool throwHint;
  // Shows once, for someone who never turned a card, that a card has a
  // back: the front card turns over and back by itself. The throw hint
  // waits for it.
  final bool turnHint;
  // The turn hint has run (or was cut short by the user).
  final VoidCallback? onTurnHinted;

  @override
  State<HandView> createState() => _HandViewState();
}

class _HandViewState extends State<HandView> with TickerProviderStateMixin {
  final _fanKey = GlobalKey<_CardFanState>();
  final _frontKey = GlobalKey();
  // Fractional index of the front card, shared by the fan and the dots.
  final _position = ValueNotifier<double>(0);
  // A card is lifted: the trash can takes the dots' place.
  final _carrying = ValueNotifier<bool>(false);
  // The lifted card is over the trash can.
  final _overTrash = ValueNotifier<bool>(false);
  final _trashKey = GlobalKey();
  // Cards taken into the hand from "Alle ansehen", most recent first.
  final _pulled = <String>[];
  // Thrown off the hand while the reason sheet is open.
  final _away = <String>{};
  late final AnimationController _flight;
  // Runs the throw hint: the dip and the line, which then waits until the
  // user swipes or lifts a card, and fades out.
  late final AnimationController _hint;
  // The front card is still to turn over and back once.
  late bool _peek = widget.turnHint;

  bool get _throwHinted => widget.throwHint && widget.onThrow != null;

  @override
  void initState() {
    super.initState();
    _flight = AnimationController(vsync: this, duration: MiMotion.flight);
    // Kept at full length when the phone turns animations off: it carries
    // words to read, and the card does not move then anyway.
    _hint = AnimationController(
      vsync: this,
      duration: _hintDuration,
      animationBehavior: AnimationBehavior.preserve,
    );
    if (_throwHinted && !_peek) _showHint();
    _position.addListener(_onPosition);
    _carrying.addListener(_onCarrying);
  }

  void _peeked() {
    if (!_peek || !mounted) return;
    setState(() => _peek = false);
    widget.onTurnHinted?.call();
    if (_throwHinted) _showHint();
  }

  // Shown after the turn, when the eyes may still be on the card, so the
  // line stays until the user swipes or lifts a card.
  void _showHint() => _hint.animateTo(_hintHold);

  void _endHint() {
    if (_hint.value == 0 || _hint.value >= _hintOut) return;
    _hint.value = _hintOut;
    _hint.forward();
  }

  void _onPosition() {
    if (_position.value.round() != 0) _endHint();
  }

  void _onCarrying() {
    if (_carrying.value) _endHint();
  }

  @override
  void dispose() {
    _position.removeListener(_onPosition);
    _carrying.removeListener(_onCarrying);
    _flight.dispose();
    _hint.dispose();
    _position.dispose();
    _carrying.dispose();
    _overTrash.dispose();
    super.dispose();
  }

  List<RankedOpportunity> get _hand {
    final open = widget.opportunities
        .where((r) => !_away.contains(r.opportunity.id))
        .toList();
    final byId = {for (final r in open) r.opportunity.id: r};
    final pulled = [
      for (final id in _pulled)
        if (byId[id] case final r?) r,
    ];
    final rest =
        open.where((r) => !_pulled.contains(r.opportunity.id)).take(kHandSize);
    return [...pulled, ...rest];
  }

  Future<void> _throw(RankedOpportunity ranked, int position) async {
    final onThrow = widget.onThrow;
    if (onThrow == null) return;
    final id = ranked.opportunity.id;
    _hint.value = 1;
    setState(() => _away.add(id));
    final gone = await onThrow(ranked, position);
    if (!mounted) return;
    setState(() {
      _away.remove(id);
      if (gone) _pulled.remove(id);
    });
    if (!gone) _fanKey.currentState?.jumpTo(position);
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

  // One option of a bundle. The card does not fly: it stays in the hand
  // with the option ticked while others are open, and simply leaves with
  // the last one (bundleCards).
  Future<void> _playOption(RankedOpportunity option) async {
    final done = await widget.onPlay(option);
    if (!done || !mounted) return;
    widget.onPlayed(option);
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Erledigt. Die Option liegt jetzt bei deiner Wirkung.',
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

  Widget _card(
    RankedOpportunity ranked, {
    required bool isFront,
    required double contentOpacity,
    required double drift,
  }) =>
      ActionCard(
        // The front card's GlobalKey moves to the next card on a swipe;
        // keyed by action, the next one does not inherit the turned-over
        // state and starts face up.
        key: ValueKey(ranked.opportunity.id),
        ranked: ranked,
        actionLabel: widget.actionLabel(ranked.opportunity),
        isFront: isFront,
        contentOpacity: contentOpacity,
        drift: drift,
        onAction: isFront ? () => _play(ranked) : null,
        onOption: isFront ? _playOption : null,
        doneIds: widget.doneIds,
        onOpened: () => widget.onOpened?.call(ranked),
        peek: isFront && _peek,
        onPeeked: _peeked,
      );

  @override
  Widget build(BuildContext context) {
    final hand = _hand;
    final total = widget.opportunities.length - _away.length;
    // No header: the tab already says "Für dich" and the dots count the
    // cards, so the space goes to the cards.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: MiSpace.base),
        Expanded(
          child: AnimatedBuilder(
            animation: _hint,
            builder: (context, child) => _CardFan(
              key: _fanKey,
              cards: hand,
              position: _position,
              carrying: _carrying,
              overTrash: _overTrash,
              trashKey: _trashKey,
              frontKey: _frontKey,
              nudge: MiMotion.reduced(context) ? 0 : _hintLift(_hint.value),
              onThrow: widget.onThrow == null
                  ? null
                  : (index) => _throw(hand[index], index),
              builder: _card,
              endCard: ({required isFront, required contentOpacity}) =>
                  _EndCard(
                dealt: hand.length,
                total: total,
                contentOpacity: contentOpacity,
                onShowAll: _showAll,
                onRestart: () => _fanKey.currentState?.animateTo(0),
              ),
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
          child: AnimatedBuilder(
            animation: Listenable.merge([_position, _carrying, _hint]),
            builder: (context, _) {
              final position = _position.value;
              final hinting = _hint.value > 0 && _hint.value < 1;
              // One height for dots, link and trash, so the hand never
              // jumps when they swap.
              final fade =
                  MiMotion.reduced(context) ? Duration.zero : MiMotion.quick;
              final carrying = _carrying.value;
              return SizedBox(
                height: 48,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: carrying ? 0 : 1,
                        duration: fade,
                        child: IgnorePointer(
                          ignoring: carrying,
                          child: Row(
                            children: [
                              _Dots(count: hand.length + 1, position: position),
                              // While it runs, the throw hint stands in for
                              // the link.
                              if (hinting)
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _ThrowHint(t: _hint.value),
                                  ),
                                )
                              else ...[
                                const Spacer(),
                                // The closing card carries its own "Alle
                                // ansehen".
                                if (total > 1 && position.round() < hand.length)
                                  TextButton(
                                    onPressed: _showAll,
                                    child: Text('Alle $total ansehen'),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: carrying ? 1 : 0,
                        duration: fade,
                        child: _Trash(targetKey: _trashKey, hot: _overTrash),
                      ),
                    ),
                  ],
                ),
              );
            },
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
  required double drift,
});

const _hintDuration = Duration(milliseconds: 6500);
// Where the throw hint waits, its line fully shown, and where it fades out
// from (see _ThrowHint).
const _hintHold = 0.5;
const _hintOut = 0.88;

/// How far the throw hint lifts the front card at [t] of the hint, 0-1:
/// up and down once, early on, as a long press would.
double _hintLift(double t) {
  const start = 0.12, length = 0.14;
  if (t < start || t > start + length) return 0;
  return sin((t - start) / length * pi);
}

/// Where a lifted card is dropped to be thrown away. It warms up (coral)
/// while the card is over it.
class _Trash extends StatelessWidget {
  const _Trash({required this.targetKey, required this.hot});

  // On the can itself, to tell when a card is over it.
  final GlobalKey targetKey;
  final ValueListenable<bool> hot;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Center(
      child: ValueListenableBuilder(
        valueListenable: hot,
        builder: (context, hot, _) => AnimatedScale(
          key: targetKey,
          scale: hot ? 1.25 : 1,
          duration: MiMotion.quick,
          curve: MiMotion.ease,
          child: AnimatedContainer(
            duration: MiMotion.quick,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: hot ? colors.topics[0] : colors.tableRaised,
              shape: BoxShape.circle,
              border: Border.all(
                color: hot ? colors.topics[0] : colors.onTableMuted,
              ),
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              semanticLabel: 'Papierkorb',
              color: hot ? colors.onCard : colors.onTable,
            ),
          ),
        ),
      ),
    );
  }
}

/// The throw hint's words next to the dots, at [t] of the hint: in with
/// the lift, out at the end.
class _ThrowHint extends StatelessWidget {
  const _ThrowHint({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final opacity = min(
      ((t - 0.08) / 0.06).clamp(0.0, 1.0),
      ((1 - t) / (1 - _hintOut)).clamp(0.0, 1.0),
    );
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline_rounded,
              size: 16,
              color: colors.onTableMuted,
            ),
            const SizedBox(width: MiSpace.xs),
            Flexible(
              child: Text(
                'Lange drücken zum Weglegen',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: colors.onTableMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _EndBuilder = Widget Function({
  required bool isFront,
  required double contentOpacity,
});

/// The fanned cards: the front one upright, the next ones peeking out to
/// the right behind it, and a closing card after the last one, so the hand
/// has an end. A horizontal swipe moves through it and snaps to a card.
/// A long press lifts the front card, on either face; it then follows the
/// finger. Dropped on the trash can ([trashKey]) it shrinks into it and
/// goes to [onThrow]; dropped anywhere else it glides back into the hand.
class _CardFan extends StatefulWidget {
  const _CardFan({
    required this.cards,
    required this.position,
    required this.frontKey,
    required this.builder,
    required this.endCard,
    required this.carrying,
    required this.overTrash,
    required this.trashKey,
    this.onThrow,
    this.nudge = 0,
    super.key,
  });

  final List<RankedOpportunity> cards;
  final ValueNotifier<double> position;
  // A card is lifted, so the trash can shows.
  final ValueNotifier<bool> carrying;
  // The lifted card is over the trash can.
  final ValueNotifier<bool> overTrash;
  final GlobalKey trashKey;
  final GlobalKey frontKey;
  final _CardBuilder builder;
  final _EndBuilder endCard;
  // The index of the card dropped in the trash.
  final ValueChanged<int>? onThrow;
  // Extra lift of the front card (0-1), for the throw hint.
  final double nudge;

  @override
  State<_CardFan> createState() => _CardFanState();
}

class _CardFanState extends State<_CardFan> with TickerProviderStateMixin {
  ValueNotifier<double> get position => widget.position;
  late final AnimationController _snap;
  // 0-1: how far the front card is lifted off the hand.
  late final AnimationController _lift;
  // 0-1: a dropped card on its way back, or into the trash.
  late final AnimationController _settle;
  // Where the finger has carried the lifted card.
  Offset _carry = Offset.zero;
  // Where the finger holds the card, from its middle.
  Offset _grip = Offset.zero;
  Offset _settleTo = Offset.zero;
  bool _binning = false;
  bool _busy = false;
  double _cardWidth = 300;
  bool _hideFront = false;

  set hideFront(bool value) => setState(() => _hideFront = value);

  // The closing card sits right after the last action card.
  int get _last => widget.cards.length;

  bool get _canLift =>
      widget.onThrow != null &&
      !_busy &&
      position.value.round() < widget.cards.length;

  // The front card's offset from its place: carried, or settling.
  Offset get _offset {
    final t = MiMotion.ease.transform(_settle.value);
    return Offset.lerp(_carry, _settleTo, t)!;
  }

  void _onLiftStart(LongPressStartDetails details) {
    if (!_canLift) return;
    _snap.stop();
    position.value = position.value.roundToDouble();
    _carry = Offset.zero;
    final size = context.size;
    _grip = size == null
        ? Offset.zero
        : details.localPosition - size.center(Offset.zero);
    _settle.value = 0;
    widget.carrying.value = true;
    if (MiMotion.reduced(context)) {
      _lift.value = 1;
    } else {
      _lift.forward(from: 0);
    }
  }

  void _onLiftMove(LongPressMoveUpdateDetails details) {
    if (!widget.carrying.value || _busy) return;
    setState(() => _carry = details.offsetFromOrigin);
    widget.overTrash.value = _overTrash(details.globalPosition);
  }

  Future<void> _onLiftEnd(LongPressEndDetails details) async {
    if (!widget.carrying.value || _busy) return;
    final index = position.value.round();
    final drop = _overTrash(details.globalPosition);
    _busy = true;
    _binning = drop;
    _settleTo = drop ? _trashOffset() ?? _carry : Offset.zero;
    if (MiMotion.reduced(context)) {
      _settle.value = 1;
    } else {
      await _settle.animateTo(
        1,
        duration: drop ? MiMotion.settle : MiMotion.flip,
        curve: Curves.linear,
      );
    }
    if (!mounted) return;
    widget.overTrash.value = false;
    widget.carrying.value = false;
    if (drop) widget.onThrow?.call(index);
    setState(() {
      _carry = Offset.zero;
      _settleTo = Offset.zero;
      _lift.value = 0;
      _settle.value = 0;
      _binning = false;
      _busy = false;
    });
  }

  bool _overTrash(Offset global) {
    final box =
        widget.trashKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    // The can and a fingertip around it.
    return (box.localToGlobal(Offset.zero) & box.size)
        .inflate(28)
        .contains(global);
  }

  // From the front card's place to the middle of the trash can.
  Offset? _trashOffset() {
    final trash =
        widget.trashKey.currentContext?.findRenderObject() as RenderBox?;
    final fan = context.findRenderObject() as RenderBox?;
    if (trash == null || fan == null) return null;
    return trash.localToGlobal(trash.size.center(Offset.zero)) -
        fan.localToGlobal(fan.size.center(Offset.zero));
  }

  @override
  void initState() {
    super.initState();
    _snap = AnimationController.unbounded(vsync: this)
      ..addListener(() => position.value = _snap.value);
    _lift = AnimationController(vsync: this, duration: MiMotion.quick)
      ..addListener(_onMove);
    _settle = AnimationController(vsync: this)..addListener(_onMove);
    position.addListener(_onMove);
    widget.overTrash.addListener(_onMove);
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
    widget.overTrash.removeListener(_onMove);
    _snap.dispose();
    _lift.dispose();
    _settle.dispose();
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
        final throwable = widget.onThrow != null && front < cards.length;
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
          customSemanticsActions: throwable
              ? {
                  const CustomSemanticsAction(label: 'Karte weglegen'): () =>
                      widget.onThrow?.call(front),
                }
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _onDrag,
            onHorizontalDragEnd: _onDragEnd,
            onLongPressStart: throwable ? _onLiftStart : null,
            onLongPressMoveUpdate: throwable ? _onLiftMove : null,
            onLongPressEnd: throwable ? _onLiftEnd : null,
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
                            drift: i - pos,
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
    // Lifted, the front card grows a little and tilts with the finger.
    // Over the trash it shrinks, so the can shows; dropped in, it shrinks
    // away into it.
    final settle = _settle.value;
    final lift = isFront
        ? max(_lift.value * (_binning ? 1 : 1 - settle), widget.nudge)
        : 0.0;
    final carried = isFront ? _offset : Offset.zero;
    final hot = isFront && widget.overTrash.value;
    final binned = isFront && _binning ? 1 - 0.88 * settle : 1.0;
    // Carried down towards the can, the card gets smaller, so it stays in
    // sight above the tab bar: under half its size by the can.
    final toward = isFront ? (carried.dy / (height * 0.6)).clamp(0.0, 1.0) : 0;
    final shrink = 1 - 0.55 * toward;
    // Fanned like a hand held up: the cards behind turn up about their
    // bottom right corner, so they peek out above it to the right.
    final dx = behind * 8 + leaving * (width + 60);
    final angle = behind * 0.07 - leaving * 0.12 + carried.dx * 0.0008;
    final scale = (1 - 0.02 * behind) * (1 + 0.05 * lift) * shrink * binned;
    // Towards the can, the card moves up over the finger until its lower
    // edge rests on the can, so it stays in sight above the tab bar; as it
    // drops in, it lets go of that.
    final held = isFront && (widget.carrying.value || _busy)
        ? (_grip - Offset(0, height * scale / 2)) *
            toward.toDouble() *
            (_binning ? 1 - settle : 1)
        : Offset.zero;
    final fade = isFront && _binning
        ? (1 - max(0.0, settle - 0.6) / 0.4).clamp(0.0, 1.0)
        : 1.0;
    // While the front card is lifted, the next one shows its words: it is
    // the one that moves up.
    final next = (delta - 1).abs() < 0.5
        ? _lift.value * (_binning ? 1 : 1 - settle)
        : 0.0;
    final card = SizedBox(
      key: isFront ? widget.frontKey : null,
      width: width,
      height: height,
      child: build(max((1 - behind * 2).clamp(0.0, 1.0), next)),
    );
    return Transform.translate(
      key: key,
      offset: Offset(dx, 0) + carried + held,
      child: Transform.rotate(
        angle: angle,
        alignment: behind > 0 ? Alignment.bottomRight : Alignment.bottomCenter,
        child: Transform.scale(
          scale: scale,
          child: AnimatedScale(
            scale: hot ? 0.8 : 1,
            duration:
                MiMotion.reduced(context) ? Duration.zero : MiMotion.quick,
            curve: MiMotion.ease,
            child: Opacity(
              opacity: isFront && _hideFront ? 0 : fade,
              child: IgnorePointer(ignoring: !isFront, child: card),
            ),
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
                              !more
                                  ? 'Das waren alle offenen Aktionen.'
                                  : dealt == 1
                                      ? 'Das war die Aktion, die am besten '
                                          'zu dir passt.'
                                      : 'Das waren die $dealt, die am '
                                          'besten zu dir passen.',
                              textAlign: TextAlign.center,
                              style: text.titleLarge
                                  ?.copyWith(color: colors.onCard),
                            ),
                            const SizedBox(height: MiSpace.sm),
                            Text(
                              more
                                  ? 'Ausgesucht nach deinen Werten und dem, '
                                      'was dich betrifft. Gerade sind '
                                      'insgesamt $total Aktionen offen.'
                                  : 'Neue kommen dazu, sobald Region, Land '
                                      'oder EU sie veröffentlichen.',
                              textAlign: TextAlign.center,
                              style: text.bodyMedium
                                  ?.copyWith(color: colors.onCardMuted),
                            ),
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
                style: colors.tableButton.copyWith(
                  minimumSize: const WidgetStatePropertyAll(Size(200, 52)),
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
