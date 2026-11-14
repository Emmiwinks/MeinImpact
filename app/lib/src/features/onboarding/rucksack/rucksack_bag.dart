import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/mi_theme.dart';
import '../../feed/domain/lebenslage.dart';
import '../../feed/domain/lebenslagen_catalog.g.dart';
import '../../feed/presentation/widgets/werte_bild.dart';
import 'hanging_tag.dart';

/// [ids] as they lie in the bag when packed earlier: each in its area's
/// colour, public and private ones numbered into their own slots.
List<PackedItem> packedLebenslagen(Iterable<String> ids, List<Color> topics) {
  var public = 0;
  var private = 0;
  return [
    for (final id in ids)
      if (lebenslageById[id] case final item?)
        PackedItem(
          id: id,
          color: lebenslageColor(item, topics),
          slot: item.isPrivate ? private++ : public++,
          isPrivate: item.isPrivate,
        ),
  ];
}

/// The colour of [item]'s area, as on its area card.
Color lebenslageColor(Lebenslage item, List<Color> topics) =>
    topics[math.max(kLebenslageAreas.indexOf(item.area), 0) % topics.length];

/// Something packed: a public Lebenslage sticks out of the opening, a
/// private one out of the Privatfach at the front. [slot] places it and
/// stays fixed while it is in the bag, so nothing shifts when another one
/// comes out.
@immutable
class PackedItem {
  const PackedItem({
    required this.id,
    required this.color,
    required this.slot,
    required this.isPrivate,
    this.entrySpeed,
    this.gravity,
  });

  final String id;
  final Color color;
  final int slot;
  final bool isPrivate;

  /// When it arrives thrown: its downward speed at the drop point (sheet
  /// units per second) and the pull it falls with (per second squared), so
  /// the drop into the bag carries the throw on without a stop.
  final double? entrySpeed;
  final double? gravity;

  PackedItem thrown({required double speed, required double pull}) =>
      PackedItem(
        id: id,
        color: color,
        slot: slot,
        isPrivate: isPrivate,
        entrySpeed: speed,
        gravity: pull,
      );
}

/// The open Rucksack the onboarding packs: drawn on a 200 × 250 sheet and
/// shown [width] wide. In layers from the back: straps, handle, the lid
/// thrown back and the dark opening; the picture and the public tags; the
/// front with the Privatfach's slit; the private tags; the Privatfach's
/// front. Packed things drop in from above the opening, the bag gives a
/// little squash when they land, and they drop out again when unpacked.
class RucksackBag extends StatefulWidget {
  const RucksackBag({
    required this.width,
    required this.items,
    this.answers,
    this.dropPicture = false,
    this.plz,
    this.place,
    super.key,
  });

  final double width;
  final List<PackedItem> items;

  /// The value answers for "Dein Bild", framed and packed first; null
  /// without any answers.
  final List<double?>? answers;

  /// Drops the picture in when the bag first shows.
  final bool dropPicture;

  /// The luggage tag hanging from the strap, once a PLZ is given.
  final String? plz;
  final String? place;

  static const sheet = Size(200, 250);

  /// How far above its resting place [item] starts its drop: down through
  /// the opening, or a shorter way into the Privatfach.
  static double fallOf(PackedItem item) => item.isPrivate ? 44 : 70;

  /// The size of [item]'s tag top on the sheet, and its tilt in degrees
  /// (the tilt it starts its drop with is 40% of that).
  static (Size, double) tagOf(PackedItem item) {
    final s = _Slot.of(item);
    return (Size(s.width, s.height), s.turn);
  }

  /// The colour of the bag's inside, which shows through a tag's eyelet.
  static Color innerOf(BuildContext context) =>
      (Theme.of(context).brightness == Brightness.dark
              ? _BagColors.dark
              : _BagColors.light)
          .inner;

  @override
  State<RucksackBag> createState() => RucksackBagState();
}

class RucksackBagState extends State<RucksackBag>
    with TickerProviderStateMixin {
  late final _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final _sway = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
    value: 1,
  );
  late final _picture = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: widget.dropPicture ? 0 : 1,
  );

  // Unpacked things, still dropping out of sight.
  final _leaving = <PackedItem>[];
  // Whether the first frame is built: items present from the start lie
  // still, later ones drop in.
  bool _built = false;

  double get _scale => widget.width / RucksackBag.sheet.width;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _built = true;
      final reduced = MiMotion.reduced(context);
      if (widget.dropPicture && widget.answers != null) {
        if (reduced) {
          _picture.value = 1;
        } else {
          _picture.forward().then((_) {
            if (mounted) bump();
          });
        }
      }
    });
  }

  @override
  void didUpdateWidget(RucksackBag oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final item in widget.items) item.id};
    for (final item in oldWidget.items) {
      if (!ids.contains(item.id)) _leaving.add(item);
    }
    _leaving.removeWhere((l) => ids.contains(l.id));
    // The luggage tag swings out when it is hung on.
    if (oldWidget.plz == null && widget.plz != null) {
      if (!MiMotion.reduced(context)) _sway.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    _sway.dispose();
    _picture.dispose();
    super.dispose();
  }

  /// The little squash of something landing in the bag.
  void bump() {
    HapticFeedback.lightImpact();
    if (MiMotion.reduced(context)) return;
    _bump.forward(from: 0);
  }

  /// Where [item] starts its drop, in global coordinates: the top centre of
  /// its tag, [RucksackBag.fallOf] above where it comes to rest.
  Offset? dropPoint(PackedItem item) {
    final g = _Slot.of(item);
    return _toGlobal(
      Offset(g.x + g.width / 2, g.top - RucksackBag.fallOf(item)),
    );
  }

  /// Where the luggage tag hangs, in global coordinates (its centre).
  Offset? luggagePoint() => _toGlobal(const Offset(-40, 124));

  Offset? _toGlobal(Offset onSheet) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(onSheet * _scale);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = dark ? _BagColors.dark : _BagColors.light;
    final reduced = MiMotion.reduced(context);

    Widget packed(PackedItem item, {required bool leaving}) => _Packed(
          key: ValueKey('${item.id}-${leaving ? 'out' : 'in'}'),
          item: item,
          inner: palette.inner,
          dropIn: _built && !leaving && !reduced,
          leaving: leaving,
          onLanded: bump,
          onGone: () => setState(() => _leaving.remove(item)),
        );

    final public = [
      for (final item in widget.items)
        if (!item.isPrivate) packed(item, leaving: false),
      for (final item in _leaving)
        if (!item.isPrivate) packed(item, leaving: true),
    ];
    final private = [
      for (final item in widget.items)
        if (item.isPrivate) packed(item, leaving: false),
      for (final item in _leaving)
        if (item.isPrivate) packed(item, leaving: true),
    ];

    return SizedBox(
      width: widget.width,
      height: RucksackBag.sheet.height * _scale,
      child: FittedBox(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: RucksackBag.sheet,
          child: AnimatedBuilder(
            animation: _bump,
            builder: (context, child) {
              final t = _bump.value;
              // Squash, stretch, settle.
              final sx = 1 + 0.05 * math.sin(t * math.pi) * (1 - t);
              final sy = 1 - 0.08 * math.sin(t * math.pi) * (1 - t) * 1.2;
              return Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(sx, sy, 1),
                child: child,
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _BackPainter(palette)),
                ),
                if (widget.answers != null)
                  _DroppingPicture(
                    animation: _picture,
                    answers: widget.answers!,
                  ),
                ...public,
                Positioned.fill(
                  child: CustomPaint(painter: _FrontPainter(palette)),
                ),
                ...private,
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PocketPainter(
                      palette,
                      Theme.of(context).textTheme.labelMedium!,
                    ),
                  ),
                ),
                if (widget.plz != null)
                  Positioned(
                    left: -86,
                    top: 92,
                    child: AnimatedBuilder(
                      animation: _sway,
                      builder: (context, child) => Transform.rotate(
                        alignment: const Alignment(0.84, -1),
                        angle: (7 +
                                16 *
                                    math.exp(-3.5 * _sway.value) *
                                    math.sin(_sway.value * 5 * math.pi)) *
                            math.pi /
                            180,
                        child: child,
                      ),
                      child: LuggageTag(
                        plz: widget.plz!,
                        place: widget.place,
                        cord: palette.trim,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The PLZ on an amber luggage tag, its cord running up to the strap.
class LuggageTag extends StatelessWidget {
  const LuggageTag({
    required this.plz,
    this.place,
    this.cord,
    super.key,
  });

  final String plz;
  final String? place;
  final Color? cord;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return SizedBox(
      width: 100,
      height: 74,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (cord != null)
            Positioned.fill(
              child: CustomPaint(painter: _LuggageCordPainter(cord!)),
            ),
          Positioned(
            left: 0,
            top: 18,
            width: 96,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 22, 7),
              decoration: ShapeDecoration(
                color: colors.topics[2],
                shape:
                    const TagBorder(notch: 13, radius: 7, notchOnRight: true),
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    plz,
                    style: TextStyle(
                      fontFamily: MiFonts.display,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.1,
                      letterSpacing: -0.3,
                      color: colors.onCard,
                    ),
                  ),
                  if (place != null)
                    Text(
                      place!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: MiFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        height: 1.3,
                        color: colors.onCard,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // The eyelet the cord runs through.
          Positioned(
            left: 81,
            top: 18 + 20,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.table,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 2.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LuggageCordPainter extends CustomPainter {
  _LuggageCordPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(84, 0)
        ..cubicTo(90, 12, 92, 26, 85.5, 42),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LuggageCordPainter old) => old.color != color;
}

/// The framed picture, falling into the bag from high above and settling
/// at the back of the opening.
class _DroppingPicture extends StatelessWidget {
  const _DroppingPicture({required this.animation, required this.answers});

  final Animation<double> animation;
  final List<double?> answers;

  static final _fall = TweenSequence<Offset>([
    TweenSequenceItem(
      tween: Tween(begin: const Offset(-6, -230), end: const Offset(0, -50))
          .chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 60,
    ),
    TweenSequenceItem(
      tween: Tween(begin: const Offset(0, -50), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 40,
    ),
  ]);
  static final _size = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 2.4, end: 1), weight: 60),
    TweenSequenceItem(tween: ConstantTween(1), weight: 40),
  ]);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 68,
      top: 22,
      width: 64,
      height: 64,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = animation.value;
          return Transform.translate(
            offset: _fall.transform(t),
            child: Transform.rotate(
              angle: (-4 + 9 * t) * math.pi / 180,
              child: Transform.scale(scale: _size.transform(t), child: child),
            ),
          );
        },
        child: _MiniFrame(answers: answers),
      ),
    );
  }
}

/// "Dein Bild" in a small ink frame with a light mat.
class _MiniFrame extends StatelessWidget {
  const _MiniFrame({required this.answers});

  final List<double?> answers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.mi.keyline),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: WerteBild(answers: answers),
      ),
    );
  }
}

/// Where a packed thing rests, on the bag's sheet: public tags spread to
/// both sides of the opening (the middle kept for the picture) at varied
/// heights and tilts; private ones along the Privatfach's slit.
class _Slot {
  const _Slot(this.x, this.top, this.width, this.height, this.turn);

  factory _Slot.of(PackedItem item) {
    final n = item.slot;
    if (item.isPrivate) {
      const xs = [66.0, 104.0, 84.0, 122.0, 58.0, 96.0];
      return _Slot(xs[n % xs.length], 150, 18, 40, ((n * 41) % 11) - 5.0);
    }
    const xs = [
      30.0,
      132.0,
      48.0,
      116.0,
      22.0,
      140.0,
      62.0,
      104.0,
      38.0,
      124.0,
    ];
    final x = xs[n % xs.length];
    final h = 54.0 + (n * 37) % 22;
    final turn = (x < 86 ? -1 : 1) * (4.0 + (n * 53) % 9);
    return _Slot(x, 70 - h, 30, h + 44, turn);
  }

  final double x;
  final double top;
  final double width;
  final double height;

  /// Degrees.
  final double turn;
}

/// One packed tag: drops in from above, lies still, and drops out of sight
/// when unpacked.
class _Packed extends StatefulWidget {
  const _Packed({
    required this.item,
    required this.inner,
    required this.dropIn,
    required this.leaving,
    required this.onLanded,
    required this.onGone,
    super.key,
  });

  final PackedItem item;
  final Color inner;
  final bool dropIn;
  final bool leaving;
  final VoidCallback onLanded;
  final VoidCallback onGone;

  @override
  State<_Packed> createState() => _PackedState();
}

class _PackedState extends State<_Packed> with SingleTickerProviderStateMixin {
  late final _move = AnimationController(vsync: this, duration: _duration);

  // A thrown tag keeps falling at the speed it arrived with, under the same
  // pull: k is the share of the way covered by that speed alone.
  late final double _k;

  Duration get _duration {
    if (widget.leaving) return const Duration(milliseconds: 260);
    final v = widget.item.entrySpeed;
    final g = widget.item.gravity;
    final fall = RucksackBag.fallOf(widget.item);
    if (v == null || g == null || g <= 0) {
      _k = 0;
      return const Duration(milliseconds: 300);
    }
    final seconds = (-v + math.sqrt(v * v + 2 * g * fall)) / g;
    _k = (v * seconds / fall).clamp(0.0, 1.0);
    return Duration(
      milliseconds: (seconds * 1000).round().clamp(40, 400),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.leaving) {
      _move.forward().then((_) => widget.onGone());
    } else if (widget.dropIn) {
      _move.forward().then((_) {
        if (mounted) widget.onLanded();
      });
    } else {
      _move.value = 1;
    }
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = _Slot.of(widget.item);
    final private = widget.item.isPrivate;
    final fall = RucksackBag.fallOf(widget.item);
    return Positioned(
      left: slot.x,
      top: slot.top,
      width: slot.width,
      height: slot.height,
      child: AnimatedBuilder(
        animation: _move,
        builder: (context, child) {
          final x = _move.value;
          // Leaving: a plain fall. Arriving: the throw carried on.
          final t = widget.leaving ? x * x : _k * x + (1 - _k) * x * x;
          final dy = widget.leaving ? t * (fall + 30) : -(1 - t) * fall;
          final turn = widget.leaving ? slot.turn : slot.turn * (0.4 + 0.6 * t);
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              alignment: Alignment.bottomCenter,
              angle: turn * math.pi / 180,
              child: child,
            ),
          );
        },
        child: PackedTagTop(
          color: widget.item.color,
          inner: widget.inner,
          small: private,
        ),
      ),
    );
  }
}

/// The top of a packed tag as it sticks out: rounded top, an eyelet. Also
/// what flies from the area card into the bag.
class PackedTagTop extends StatelessWidget {
  const PackedTagTop({
    super.key,
    required this.color,
    required this.inner,
    required this.small,
  });

  final Color color;
  final Color inner;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(small ? 6 : 9),
          bottom: const Radius.circular(2),
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: small ? 5 : 8),
          child: Container(
            width: small ? 6 : 8,
            height: small ? 6 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: inner,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: small ? 1.5 : 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bag's own colours: one tan canvas on both tables, apart from the
/// card stock and the light table alike. Only the shadow it stands on
/// follows the table.
class _BagColors {
  const _BagColors({
    required this.body,
    required this.trim,
    required this.inner,
    required this.ground,
  });

  final Color body;
  final Color trim;
  final Color inner;
  final Color ground;

  static const dark = _BagColors(
    body: Color(0xFFE9D8BC),
    trim: Color(0xFFCDB48E),
    inner: Color(0xFF4A4440),
    ground: Color(0x73000000),
  );
  static const light = _BagColors(
    body: Color(0xFFE9D8BC),
    trim: Color(0xFFCDB48E),
    inner: Color(0xFF4A4440),
    ground: Color(0x38785428),
  );
}

/// The shadow it stands on, straps, handle, the lid thrown back and the
/// opening.
class _BackPainter extends CustomPainter {
  _BackPainter(this.c);

  final _BagColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final trim = Paint()..color = c.trim;
    canvas
      ..drawOval(
        Rect.fromCenter(center: const Offset(100, 246), width: 172, height: 18),
        Paint()
          ..color = c.ground
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawRRect(
        RRect.fromLTRBR(0, 96, 18, 214, const Radius.circular(9)),
        trim,
      )
      ..drawRRect(
        RRect.fromLTRBR(182, 96, 200, 214, const Radius.circular(9)),
        trim,
      )
      ..drawPath(
        Path()
          ..moveTo(76, 52)
          ..cubicTo(76, 6, 124, 6, 124, 52),
        Paint()
          ..color = c.trim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(
        Path()
          ..moveTo(22, 60)
          ..cubicTo(20, 26, 54, 14, 100, 14)
          ..cubicTo(146, 14, 180, 26, 178, 60)
          ..close(),
        trim,
      )
      ..drawRRect(
        RRect.fromLTRBR(88, 16, 112, 32, const Radius.circular(6)),
        Paint()..color = const Color(0xD9101820),
      )
      ..drawOval(
        Rect.fromCenter(center: const Offset(100, 64), width: 168, height: 36),
        Paint()..color = c.inner,
      );
  }

  @override
  bool shouldRepaint(_BackPainter old) => old.c != c;
}

/// The front of the bag, its rim, and the Privatfach's back with the slit.
class _FrontPainter extends CustomPainter {
  _FrontPainter(this.c);

  final _BagColors c;

  @override
  void paint(Canvas canvas, Size size) {
    const rim = Offset(16, 64);
    canvas
      ..drawPath(
        Path()
          ..moveTo(rim.dx, rim.dy)
          ..cubicTo(50, 92, 150, 92, 184, 64)
          ..lineTo(186, 200)
          ..quadraticBezierTo(186, 244, 142, 244)
          ..lineTo(58, 244)
          ..quadraticBezierTo(14, 244, 14, 200)
          ..close(),
        Paint()..color = c.body,
      )
      ..drawPath(
        Path()
          ..moveTo(rim.dx, rim.dy)
          ..cubicTo(50, 92, 150, 92, 184, 64),
        Paint()
          ..color = c.trim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      )
      ..drawRRect(
        RRect.fromLTRBR(40, 152, 160, 226, const Radius.circular(24)),
        Paint()..color = c.trim,
      )
      ..drawRRect(
        RRect.fromLTRBR(52, 164, 148, 171, const Radius.circular(3.5)),
        Paint()..color = c.inner,
      );
  }

  @override
  bool shouldRepaint(_FrontPainter old) => old.c != c;
}

/// The Privatfach's front, in front of what is in it: stitching and its
/// name.
class _PocketPainter extends CustomPainter {
  _PocketPainter(this.c, this.label);

  final _BagColors c;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(40, 168)
        ..lineTo(160, 168)
        ..lineTo(160, 202)
        ..quadraticBezierTo(160, 226, 136, 226)
        ..lineTo(64, 226)
        ..quadraticBezierTo(40, 226, 40, 202)
        ..close(),
      Paint()..color = c.trim,
    );
    final stitch = Paint()
      ..color = c.body
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var x = 56.0; x < 144; x += 7) {
      canvas.drawLine(Offset(x, 186), Offset(x + 3, 186), stitch);
    }
    final name = TextPainter(
      text: TextSpan(
        text: 'Privatfach',
        style: label.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF4A5560),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    name.paint(canvas, Offset(100 - name.width / 2, 200));
  }

  @override
  bool shouldRepaint(_PocketPainter old) => old.c != c || old.label != label;
}
