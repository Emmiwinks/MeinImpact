import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/mi_theme.dart';

/// A Lebenslage as a hanging tag on an area card: a notched left end with an
/// eyelet and a loose cord, lying a little askew with a soft shadow. Once
/// packed it stays behind as a faint outline, and tapping that takes it out
/// again.
class HangingTag extends StatelessWidget {
  const HangingTag({
    required this.label,
    required this.color,
    required this.packed,
    required this.onTap,
    this.isPrivate = false,
    this.tilt = 0,
    super.key,
  });

  final String label;
  final Color color;
  final bool packed;
  final bool isPrivate;
  final VoidCallback onTap;

  /// Degrees.
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final ink = colors.onCard;
    final face = packed ? ink.withValues(alpha: 0.42) : ink;
    return Semantics(
      button: true,
      toggled: packed,
      label: label,
      hint: isPrivate ? 'Kommt ins Privatfach' : null,
      excludeSemantics: true,
      child: Transform.rotate(
        angle: packed ? 0 : tilt * math.pi / 180,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                AnimatedContainer(
                  duration: MiMotion.reduced(context)
                      ? Duration.zero
                      : MiMotion.quick,
                  constraints: const BoxConstraints(minHeight: 42),
                  padding: const EdgeInsets.fromLTRB(26, 10, 14, 10),
                  decoration: ShapeDecoration(
                    color: packed ? ink.withValues(alpha: 0.06) : color,
                    shape: TagBorder(
                      side: packed
                          ? BorderSide(
                              color: ink.withValues(alpha: 0.22),
                              width: 1.5,
                            )
                          : BorderSide.none,
                    ),
                    shadows: packed
                        ? const []
                        : [
                            BoxShadow(
                              color: ink.withValues(alpha: 0.22),
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: Text.rich(
                    TextSpan(
                      text: label,
                      children: [
                        if (isPrivate)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: PocketGlyph(color: face, size: 14),
                            ),
                          ),
                      ],
                    ),
                    style: TextStyle(
                      fontFamily: MiFonts.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: face,
                    ),
                  ),
                ),
                // The eyelet.
                Positioned(
                  left: 9,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: packed
                          ? ink.withValues(alpha: 0.16)
                          : colors.cardStock,
                      border: packed
                          ? null
                          : Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                              width: 2,
                            ),
                    ),
                  ),
                ),
                if (!packed)
                  Positioned(
                    left: -12,
                    child: CustomPaint(
                      size: const Size(24, 18),
                      painter: _CordPainter(ink.withValues(alpha: 0.55)),
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

/// The tag's outline: one end notched at both corners (the left, or the
/// right when [notchOnRight]), the other gently rounded.
class TagBorder extends OutlinedBorder {
  const TagBorder({
    super.side,
    this.notch = 12,
    this.radius = 9,
    this.notchOnRight = false,
  });

  final double notch;
  final double radius;
  final bool notchOnRight;

  Path _path(Rect r) {
    if (notchOnRight) {
      final mirrored = _notchedLeft(Rect.fromLTWH(0, 0, r.width, r.height));
      return mirrored.transform(
        (Matrix4.identity()
              ..translateByDouble(r.right, r.top, 0, 1)
              ..scaleByDouble(-1, 1, 1, 1))
            .storage,
      );
    }
    return _notchedLeft(r);
  }

  Path _notchedLeft(Rect r) {
    final n = math.min(notch, r.height / 2);
    final rr = math.min(radius, r.height / 2);
    return Path()
      ..moveTo(r.left + n, r.top)
      ..lineTo(r.right - rr, r.top)
      ..arcToPoint(Offset(r.right, r.top + rr), radius: Radius.circular(rr))
      ..lineTo(r.right, r.bottom - rr)
      ..arcToPoint(Offset(r.right - rr, r.bottom), radius: Radius.circular(rr))
      ..lineTo(r.left + n, r.bottom)
      ..lineTo(r.left, r.bottom - n)
      ..lineTo(r.left, r.top + n)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      _path(rect.deflate(side.width / 2)),
      side.toPaint(),
    );
  }

  @override
  TagBorder copyWith({BorderSide? side}) => TagBorder(
        side: side ?? this.side,
        notch: notch,
        radius: radius,
        notchOnRight: notchOnRight,
      );

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) => TagBorder(
        side: side.scale(t),
        notch: notch * t,
        radius: radius * t,
        notchOnRight: notchOnRight,
      );
}

/// A small pocket: marks a Lebenslage that goes into the Privatfach.
class PocketGlyph extends StatelessWidget {
  const PocketGlyph({required this.color, this.size = 14, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _PocketPainter(color),
      );
}

class _PocketPainter extends CustomPainter {
  _PocketPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    canvas.scale(s);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(2.5, 4.5)
        ..lineTo(13.5, 4.5)
        ..lineTo(13.5, 10)
        ..arcToPoint(const Offset(10, 13.5), radius: const Radius.circular(3.5))
        ..lineTo(6, 13.5)
        ..arcToPoint(const Offset(2.5, 10), radius: const Radius.circular(3.5))
        ..close(),
      paint,
    );
    for (var x = 5.0; x < 11; x += 3) {
      canvas.drawLine(Offset(x, 7.5), Offset(x + 1.4, 7.5), paint);
    }
  }

  @override
  bool shouldRepaint(_PocketPainter old) => old.color != color;
}

/// The loose cord through the eyelet, curling off to the left.
class _CordPainter extends CustomPainter {
  _CordPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 1, size.height / 2)
        ..cubicTo(14, 9, 8, 2, 3, 4)
        ..cubicTo(-1, 6, 2, 13, 7, 12),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CordPainter old) => old.color != color;
}
