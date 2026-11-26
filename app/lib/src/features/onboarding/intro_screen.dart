import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/mi_theme.dart';

/// The first screen. A messy deck is shuffled on the table, five cards fly
/// up into a hand, the middle one turns over and shows only a question
/// mark: which actions fit you is still open. Then the text and the two
/// ways on. No privacy line here: the next screen is the consent.
class IntroScreen extends StatefulWidget {
  const IntroScreen({
    required this.onStart,
    required this.onLater,
    super.key,
  });

  final VoidCallback onStart;

  /// "Lieber später": skips the questions, the actions come at random.
  final VoidCallback onLater;

  /// Lets the show run again, as on a fresh app start (for the review
  /// screenshots).
  static void replay() => _IntroScreenState._played = false;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  // Coming back from the consent screen shows the finished picture, the
  // show runs once per app start.
  static bool _played = false;

  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: _pause + _length,
  );

  // The pile lies still for a moment before the shuffle starts.
  static const _pause = Duration(milliseconds: 700);
  static const _length = Duration(milliseconds: 5500);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_played || MediaQuery.disableAnimationsOf(context)) {
      _show.value = 1;
    } else if (!_show.isAnimating && _show.value == 0) {
      _played = true;
      _show.forward();
    }
  }

  @override
  void dispose() {
    _show.dispose();
    super.dispose();
  }

  /// A tap on the table skips to the end.
  void _skip() {
    if (_show.isAnimating) _show.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.table,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _show,
          builder: (context, _) {
            final v = _phase(
              _show.value,
              _pause.inMilliseconds / _show.duration!.inMilliseconds,
              1,
            );
            final words = _phase(v, 0.76, 0.92, Curves.easeOutCubic);
            final buttons = _phase(v, 0.84, 1, Curves.easeOutCubic);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _skip,
                    child: ExcludeSemantics(child: _Table(progress: v)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MiSpace.lg),
                  child: Opacity(
                    opacity: words,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - words)),
                      // One voice, one size (user decision): no heading
                      // with a smaller line under it.
                      child: Text(
                        'Es gibt viele Möglichkeiten, sich politisch zu '
                        'beteiligen.\nLass uns herausfinden, welche '
                        'Aktionen zu dir passen.',
                        textAlign: TextAlign.center,
                        style: text.bodyLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: MiSpace.lg),
                IgnorePointer(
                  ignoring: buttons < 1,
                  child: Opacity(
                    opacity: buttons,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        MiSpace.lg,
                        0,
                        MiSpace.lg,
                        MiSpace.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton(
                            onPressed: widget.onStart,
                            style: colors.tableButton,
                            child: const Text('Test starten · ca. 5 Min.'),
                          ),
                          const SizedBox(height: MiSpace.xs),
                          TextButton(
                            onPressed: widget.onLater,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Lieber später?\n',
                                    style: TextStyle(
                                      color: colors.onTableMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: 'Erst mal nur Aktionen ansehen.',
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// [v] mapped onto 0..1 between [from] and [to], eased.
double _phase(
  double v,
  double from,
  double to, [
  Curve curve = Curves.linear,
]) =>
    curve.transform(((v - from) / (to - from)).clamp(0.0, 1.0));

/// Where a card lies on the table: centre in stage units (0..1 of the
/// stage's width and height) and its turn in radians.
typedef _Lie = ({double x, double y, double turn});

_Lie _lerpLie(_Lie a, _Lie b, double t) => (
      x: a.x + (b.x - a.x) * t,
      y: a.y + (b.y - a.y) * t,
      turn: a.turn + (b.turn - a.turn) * t,
    );

/// One card of the deck: three spots it is pushed through while the deck is
/// shuffled flat on the table, and its colour.
class _DeckCard {
  const _DeckCard(this.spots, this.colorIndex);

  final List<_Lie> spots;
  final int colorIndex;
}

const _deckSize = 13;
const _handSize = 5;

/// The middle card of the hand, the one that turns over.
const _flipped = 2;

/// The same messy deck every time: a fixed seed, so the screen and the
/// review screenshots always look alike.
final List<_DeckCard> _deck = () {
  final random = math.Random(11);
  _Lie spot() => (
        x: 0.5 + (random.nextDouble() - 0.5) * 0.66,
        y: 0.83 + (random.nextDouble() - 0.5) * 0.22,
        turn: (random.nextDouble() - 0.5) * 1.6,
      );
  return [
    for (var i = 0; i < _deckSize; i++)
      _DeckCard([spot(), spot(), spot()], i % 4),
  ];
}();

/// The colours of the hand from left to right: no two alike side by side.
const _handColors = [2, 0, 1, 3, 0];

/// The top five cards of the deck go into the hand, the leftmost on the
/// table to the leftmost place in the hand, so their paths do not cross.
final List<int> _drawn = () {
  final top = [for (var i = _deckSize - _handSize; i < _deckSize; i++) i];
  return top
    ..sort((a, b) => _deck[a].spots[2].x.compareTo(_deck[b].spots[2].x));
}();

/// The table with the deck and the hand at progress [progress] of the show.
class _Table extends StatelessWidget {
  const _Table({required this.progress});

  final double progress;

  // The show, in fractions of its length.
  static const _shuffleEnd = 0.3;
  static const _flyStart = 0.28;
  static const _flyEach = 0.2;
  static const _flyStagger = 0.035;
  static const _flipStart = 0.62;
  static const _flipEnd = 0.8;

  static const _small = Size(60, 86);
  static const _big = Size(80, 116);

  @override
  Widget build(BuildContext context) {
    final v = progress;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // Hand cards hang from a point below the hand, like held in fingers.
        final handCenter = Offset(w / 2, h * 0.42);
        const radius = 380.0;
        const spread = 0.14;

        Widget place(_Lie lie, Size size, Widget card, {double lift = 0}) {
          return Positioned(
            left: lie.x * w - size.width / 2,
            top: lie.y * h - size.height / 2 - lift,
            width: size.width,
            height: size.height,
            child: Transform.rotate(angle: lie.turn, child: card),
          );
        }

        // While the deck is shuffled, each card slides from spot to spot.
        _Lie onTable(_DeckCard card) {
          final t = _phase(v, 0, _shuffleEnd);
          final first = Curves.easeInOut.transform((t * 2).clamp(0.0, 1.0));
          final second =
              Curves.easeInOut.transform((t * 2 - 1).clamp(0.0, 1.0));
          return t < 0.5
              ? _lerpLie(card.spots[0], card.spots[1], first)
              : _lerpLie(card.spots[1], card.spots[2], second);
        }

        _Lie inHand(int slot) {
          final angle = (slot - (_handSize - 1) / 2) * spread;
          final pivot = handCenter + const Offset(0, radius);
          return (
            x: (pivot.dx + radius * math.sin(angle)) / w,
            y: (pivot.dy - radius * math.cos(angle)) / h,
            turn: angle,
          );
        }

        // Once the hand is up, the rest of the deck steps back, so the
        // turned card is what the eye finds.
        final rest = 1 - 0.6 * _phase(v, _flipStart, _flipEnd);
        // Faded as one layer, so the cards do not show through each other.
        final staying = Positioned.fill(
          child: Opacity(
            opacity: rest,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < _deckSize; i++)
                  if (!_drawn.contains(i))
                    place(
                      onTable(_deck[i]),
                      _small,
                      _Back(_deck[i].colorIndex),
                    ),
              ],
            ),
          ),
        );

        final hand = <Widget>[];
        for (var slot = 0; slot < _handSize; slot++) {
          final card = _deck[_drawn[slot]];
          final start = _flyStart + slot * _flyStagger;
          final t = _phase(v, start, start + _flyEach, Curves.easeOutCubic);
          final lie = _lerpLie(onTable(card), inHand(slot), t);
          final size = Size.lerp(_small, _big, t)!;
          // A little arc on the way up.
          var lift = math.sin(math.pi * t) * 36;
          Widget face = _Back(_handColors[slot]);
          if (slot == _flipped) {
            final f = _phase(v, _flipStart, _flipEnd, Curves.easeInOutCubic);
            // The turned card rises a little out of the hand.
            lift += 14 * f;
            face = _Turning(turn: f, back: face);
          }
          hand.add(place(lie, size, face, lift: lift));
        }

        return Stack(clipBehavior: Clip.none, children: [staying, ...hand]);
      },
    );
  }
}

/// A card face down: a topic colour in a rim of card stock.
class _Back extends StatelessWidget {
  const _Back(this.colorIndex);

  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return _Card(
      color: colors.topics[colorIndex % colors.topics.length],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.color, this.child});

  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardStock, width: 4),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The middle card turning over around its upright axis, [turn] 0..1; past
/// halfway its face shows: plain card stock with a big question mark.
class _Turning extends StatelessWidget {
  const _Turning({required this.turn, required this.back});

  final double turn;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final angle = math.pi * turn;
    final showFace = angle > math.pi / 2;
    final face = _Card(
      color: colors.cardStock,
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              '?',
              style: TextStyle(
                fontFamily: MiFonts.display,
                fontWeight: FontWeight.w800,
                fontSize: 64,
                height: 1,
                color: colors.onCard,
              ),
            ),
          ),
        ),
      ),
    );
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0015)
        ..rotateY(angle)
        ..scaleByDouble(1 + 0.12 * turn, 1 + 0.12 * turn, 1, 1),
      child: showFace
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(math.pi),
              child: face,
            )
          : back,
    );
  }
}
