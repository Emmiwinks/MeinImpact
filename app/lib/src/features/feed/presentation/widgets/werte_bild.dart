import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';

/// "Dein Bild": an abstract picture made from the eight value answers. One
/// shape per axis in its colour (circle Wirtschaft, half disc Diplomatie,
/// bar Freiheit, triangle Wandel); the answers move, turn and scale them.
/// Unique to the user, but nothing in it reads as a side.
///
/// [answers] holds the eight questions in order, -2.0 to +2.0, null while
/// unanswered. The shapes of the [active] question's axis stay visible as
/// dashed outlines until answered. Changes glide over [MiMotion.settle].
/// An [edge] draws a hairline round the sheet, for when it lies unframed on
/// a table close to its own colour.
class WerteBild extends StatefulWidget {
  const WerteBild({required this.answers, this.active, this.edge, super.key});

  final List<double?> answers;
  final int? active;
  final Color? edge;

  @override
  State<WerteBild> createState() => _WerteBildState();
}

class _WerteBildState extends State<WerteBild>
    with SingleTickerProviderStateMixin {
  late final _glide = AnimationController(
    vsync: this,
    duration: MiMotion.settle,
    value: 1,
  );
  late _Pose _from = _Pose.of(widget.answers, widget.active);
  late _Pose _to = _from;

  @override
  void didUpdateWidget(WerteBild old) {
    super.didUpdateWidget(old);
    final next = _Pose.of(widget.answers, widget.active);
    if (next == _to) return;
    _from = _Pose.lerp(_from, _to, MiMotion.ease.transform(_glide.value));
    _to = next;
    if (MiMotion.reduced(context)) {
      _glide.value = 1;
    } else {
      _glide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: _glide,
        builder: (context, _) => CustomPaint(
          painter: _BildPainter(
            _Pose.lerp(_from, _to, MiMotion.ease.transform(_glide.value)),
            widget.edge,
          ),
        ),
      ),
    );
  }
}

/// The picture in a frame: an ink frame around a light mat, lying on the
/// table with the card shadow. [t] grows the frame in from nothing (0) to
/// full (1), so the picture can be framed in place.
class WerteBildRahmen extends StatelessWidget {
  const WerteBildRahmen({required this.child, this.t = 1, super.key});

  final Widget child;
  final double t;

  static const frame = 10.0;
  static const mat = 14.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Container(
      padding: EdgeInsets.all(frame * t),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: t),
        borderRadius: BorderRadius.circular(8 + 10 * t),
        border: t > 0 ? Border.all(color: colors.keyline) : null,
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: colors.shadow.a * t),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(mat * t),
        decoration: BoxDecoration(
          color: _mat.withValues(alpha: t),
          borderRadius: BorderRadius.circular(8 + 2 * t),
        ),
        child: child,
      ),
    );
  }
}

/// A number for the picture that stays the same for the same answers, but
/// cannot be read back into them ("Nr. 92 253").
String werteBildNummer(List<double?> answers) {
  var h = 0x811c9dc5;
  for (var i = 0; i < answers.length; i++) {
    final a = answers[i];
    h ^= (a == null ? 999 : (a * 10).round() + 20) + i * 7;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final n = (h % 90000 + 10000).toString();
  return 'Nr. ${n.substring(0, 2)} ${n.substring(2)}';
}

const _ink = Color(0xFF101820);
const _paper = Color(0xFFF4F1EA);
const _mat = Color(0xFFFFFCF8);
const _shapeColors = [
  Color(0xFFFF5A5F),
  Color(0xFF2EC4B6),
  Color(0xFFFFBF3C),
  Color(0xFF8C84FF),
];

/// Everything the painter needs, as numbers that can be blended: each
/// answer's value and whether it is answered (0 or 1), and which axis is
/// being asked.
@immutable
class _Pose {
  const _Pose(this.values, this.answered, this.asked);

  factory _Pose.of(List<double?> answers, int? active) => _Pose(
        [for (final a in answers) (a ?? 0).clamp(-2.0, 2.0)],
        [for (final a in answers) a == null ? 0.0 : 1.0],
        [
          for (var axis = 0; axis < 4; axis++)
            active != null && active ~/ 2 == axis ? 1.0 : 0.0,
        ],
      );

  final List<double> values;
  final List<double> answered;
  final List<double> asked;

  static _Pose lerp(_Pose a, _Pose b, double t) {
    List<double> mix(List<double> x, List<double> y) =>
        [for (var i = 0; i < x.length; i++) lerpDouble(x[i], y[i], t)!];
    return _Pose(
      mix(a.values, b.values),
      mix(a.answered, b.answered),
      mix(a.asked, b.asked),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _Pose &&
      _same(values, other.values) &&
      _same(answered, other.answered) &&
      _same(asked, other.asked);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(values),
        Object.hashAll(answered),
        Object.hashAll(asked),
      );

  static bool _same(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _BildPainter extends CustomPainter {
  _BildPainter(this.pose, this.edge);

  final _Pose pose;
  final Color? edge;

  // The picture is drawn on a 300 × 300 sheet and scaled to fit.
  static const _sheet = 300.0;

  @override
  void paint(Canvas canvas, Size size) {
    final v = pose.values;
    final scale = size.width / _sheet;
    canvas.save();
    canvas.scale(scale);
    const bounds = Rect.fromLTWH(0, 0, _sheet, _sheet);
    final sheet = RRect.fromRectAndRadius(bounds, const Radius.circular(18));
    canvas.clipRRect(sheet);
    canvas.drawRect(bounds, Paint()..color = _paper);

    // The shapes overprint each other like ink on paper.
    canvas.saveLayer(bounds, Paint());
    _shape(
      canvas,
      0,
      Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 70)),
      x: 150 + v[0] * 32,
      y: 128 + v[1] * 6,
      scale: 1 + v[1] * 0.17,
    );
    _shape(
      canvas,
      1,
      Path()
        ..moveTo(-62, 0)
        ..arcToPoint(const Offset(62, 0), radius: const Radius.circular(62))
        ..close(),
      x: 96 + v[3] * 10,
      y: 212 + v[3] * 12,
      turn: v[2] * 40,
    );
    _shape(
      canvas,
      2,
      Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-90, -17, 180, 34),
            const Radius.circular(17),
          ),
        ),
      x: 168 + v[5] * 8,
      y: 214,
      turn: v[4] * 16 - 6,
      scale: 1 + v[5] * 0.12,
    );
    _shape(
      canvas,
      3,
      Path()
        ..moveTo(0, -58)
        ..lineTo(54, 40)
        ..lineTo(-54, 40)
        ..close(),
      x: 214 + v[6] * 16,
      y: 98 - v[7] * 6,
      turn: v[6] * 8,
      scale: 1 + v[7] * 0.16,
    );

    // One ink stroke across, once half the questions are answered; it leans
    // with all answers together.
    final count = pose.answered.fold(0.0, (a, b) => a + b);
    final stroke = (count - 3).clamp(0.0, 1.0);
    if (stroke > 0) {
      final sum = v.fold(0.0, (a, b) => a + b);
      canvas.save();
      canvas.translate(150, 150 + sum * 3);
      canvas.rotate((-28 + sum * 6) * math.pi / 180);
      canvas.drawLine(
        const Offset(-120, 0),
        const Offset(120, 0),
        Paint()
          ..color = _ink.withValues(alpha: stroke)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
    canvas.restore();

    // One ink dot per answer, bigger the clearer the answer.
    for (var i = 0; i < 8; i++) {
      final a = pose.answered[i];
      canvas.drawCircle(
        Offset(34 + (i % 4) * 15, 252 + (i ~/ 4) * 15),
        2 + a * (0.5 + v[i].abs() * 2),
        Paint()..color = _ink.withValues(alpha: 0.25 + 0.75 * a),
      );
    }
    final e = edge;
    if (e != null) {
      canvas.drawRRect(
        sheet.deflate(0.5 / scale),
        Paint()
          ..color = e
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
    }
    canvas.restore();
  }

  /// Draws axis [axis]'s shape: filled once one of its two questions is
  /// answered (fully once both are), a dashed outline before that, faded
  /// while another axis is asked.
  void _shape(
    Canvas canvas,
    int axis,
    Path path, {
    required double x,
    required double y,
    double turn = 0,
    double scale = 1,
  }) {
    final a = pose.answered[axis * 2];
    final b = pose.answered[axis * 2 + 1];
    final fill = 0.55 * math.max(a, b) + 0.45 * math.min(a, b);
    final present = 0.25 + 0.75 * math.max(math.max(a, b), pose.asked[axis]);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(turn * math.pi / 180);
    canvas.scale(scale);
    if (fill > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _shapeColors[axis].withValues(alpha: fill * present)
          ..blendMode = BlendMode.multiply,
      );
    }
    final outline = 1 - math.max(a, b);
    if (outline > 0) {
      final dashes = Path();
      for (final metric in path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 12) {
          dashes.addPath(metric.extractPath(d, d + 6), Offset.zero);
        }
      }
      canvas.drawPath(
        dashes,
        Paint()
          ..color = _ink.withValues(alpha: outline * present * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 / scale,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BildPainter old) => old.pose != pose || old.edge != edge;
}
