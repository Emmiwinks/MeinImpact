import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../domain/opportunity.dart';
import '../../domain/topic_tags.g.dart';

/// A card's face colour and its art, both from the opportunity's main topic
/// (its first affected tag), so the same topic always looks the same and
/// the colours spread evenly over the topic list instead of meaning
/// anything on their own.
class TopicLook {
  const TopicLook._(this.tag, this.index);

  factory TopicLook.of(Opportunity opportunity) =>
      TopicLook.forTags(opportunity.affectedTags, opportunity.kind);

  /// For a snapshot of an opportunity, such as a done action in the log.
  factory TopicLook.forTags(List<String> affectedTags, OpportunityKind kind) {
    final tag = affectedTags.isEmpty ? null : affectedTags.first;
    final index = tag == null ? -1 : kTopicTags.indexOf(tag);
    return TopicLook._(
      index < 0 ? null : tag,
      index < 0 ? kind.index : index,
    );
  }

  final String? tag;
  final int index;

  Color face(MiColors colors) => colors.topics[index % colors.topics.length];

  Color accent(MiColors colors) =>
      colors.topics[(index + 1) % colors.topics.length];
}

/// The geometric picture for a topic: a few flat shapes in ink, card stock
/// and one accent colour on the topic's face colour. Works at band and
/// thumbnail size: the motif sits in a centred square, grounds run the
/// full width.
class TopicArt extends StatelessWidget {
  const TopicArt({required this.look, super.key});

  final TopicLook look;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return ExcludeSemantics(
      child: CustomPaint(
        painter: TopicArtPainter(
          tag: look.tag,
          face: look.face(colors),
          accent: look.accent(colors),
          ink: colors.onCard,
          stock: colors.cardStock,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// A small card for list rows: the art in a rim of card stock, so ink
/// grounds in the art never run into the ink table.
class CardThumbnail extends StatelessWidget {
  const CardThumbnail({required this.look, this.size = 56, super.key});

  final TopicLook look;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.mi.cardStock,
        borderRadius: BorderRadius.circular(MiRadius.tile),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MiRadius.tile - 3),
        child: TopicArt(look: look),
      ),
    );
  }
}

class TopicArtPainter extends CustomPainter {
  TopicArtPainter({
    required this.tag,
    required this.face,
    required this.accent,
    required this.ink,
    required this.stock,
  });

  final String? tag;
  final Color face;
  final Color accent;
  final Color ink;
  final Color stock;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = face);
    final side = min(size.width, size.height) * 0.9;
    final square = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final art =
        _Art(canvas, size, square, ink: ink, stock: stock, accent: accent);
    (_recipes[tag] ?? _fallback)(art);
  }

  @override
  bool shouldRepaint(TopicArtPainter old) =>
      old.tag != tag ||
      old.face != face ||
      old.accent != accent ||
      old.ink != ink ||
      old.stock != stock;
}

/// Drawing in unit coordinates of the motif square.
class _Art {
  _Art(
    this.canvas,
    this.size,
    this.square, {
    required this.ink,
    required this.stock,
    required this.accent,
  });

  final Canvas canvas;
  final Size size;
  final Rect square;
  final Color ink;
  final Color stock;
  final Color accent;

  Offset p(double x, double y) =>
      Offset(square.left + x * square.width, square.top + y * square.height);

  double d(double v) => v * square.width;

  Paint fill(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  Paint stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = d(width)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void circle(double x, double y, double r, Color color) =>
      canvas.drawCircle(p(x, y), d(r), fill(color));

  void rect(
    double x,
    double y,
    double w,
    double h,
    Color color, {
    double radius = 0,
  }) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(p(x, y), p(x + w, y + h)),
        Radius.circular(d(radius)),
      ),
      fill(color),
    );
  }

  Path poly(List<(double, double)> points) {
    final path = Path()
      ..moveTo(
        p(points[0].$1, points[0].$2).dx,
        p(points[0].$1, points[0].$2).dy,
      );
    for (final (x, y) in points.skip(1)) {
      final o = p(x, y);
      path.lineTo(o.dx, o.dy);
    }
    return path..close();
  }

  void shape(List<(double, double)> points, Color color) =>
      canvas.drawPath(poly(points), fill(color));

  void line(
    double x1,
    double y1,
    double x2,
    double y2,
    Color color,
    double width,
  ) =>
      canvas.drawLine(p(x1, y1), p(x2, y2), stroke(color, width));

  /// A band across the full width, from [y] (motif units) to the bottom.
  void ground(double y, Color color) => canvas.drawRect(
        Rect.fromLTRB(0, p(0, y).dy, size.width, size.height),
        fill(color),
      );
}

typedef _Recipe = void Function(_Art a);

void _fallback(_Art a) {
  a.circle(0.5, 0.5, 0.36, a.stock);
  a.circle(0.5, 0.5, 0.24, a.ink);
  a.circle(0.5, 0.5, 0.12, a.accent);
}

final Map<String, _Recipe> _recipes = {
  'Wohnen/Miete': (a) {
    a.ground(0.88, a.ink);
    a.rect(0.26, 0.45, 0.48, 0.43, a.stock);
    a.shape([(0.18, 0.48), (0.5, 0.16), (0.82, 0.48)], a.ink);
    a.rect(0.42, 0.58, 0.16, 0.16, a.accent, radius: 0.02);
  },
  'Mobilität/Verkehr': (a) {
    a.circle(0.8, 0.2, 0.1, a.stock);
    for (final x in [0.28, 0.72]) {
      a.canvas.drawCircle(a.p(x, 0.66), a.d(0.17), a.stroke(a.ink, 0.05));
    }
    a.line(0.28, 0.66, 0.47, 0.4, a.ink, 0.05);
    a.line(0.47, 0.4, 0.72, 0.66, a.ink, 0.05);
    a.line(0.47, 0.4, 0.62, 0.4, a.ink, 0.05);
    a.circle(0.47, 0.4, 0.05, a.accent);
  },
  'Arbeit/Einkommen': (a) {
    a.circle(0.76, 0.24, 0.1, a.accent);
    for (final (i, y) in [0.72, 0.58, 0.44].indexed) {
      a.rect(
        0.22 + i * 0.04,
        y,
        0.42,
        0.11,
        i.isEven ? a.stock : a.ink,
        radius: 0.05,
      );
    }
  },
  'Energie/Heizkosten': (a) {
    a.circle(0.5, 0.5, 0.38, a.stock);
    a.shape(
      [
        (0.56, 0.1),
        (0.3, 0.56),
        (0.48, 0.56),
        (0.4, 0.9),
        (0.72, 0.42),
        (0.53, 0.42),
        (0.63, 0.1),
      ],
      a.ink,
    );
  },
  'Bildung/Ausbildung': (a) {
    a.circle(0.5, 0.2, 0.09, a.ink);
    a.shape([(0.12, 0.38), (0.5, 0.48), (0.5, 0.86), (0.12, 0.76)], a.stock);
    a.shape([(0.88, 0.38), (0.5, 0.48), (0.5, 0.86), (0.88, 0.76)], a.accent);
    a.line(0.5, 0.48, 0.5, 0.86, a.ink, 0.03);
  },
  'Rente/Alter': (a) {
    a.rect(0.24, 0.1, 0.52, 0.06, a.ink, radius: 0.03);
    a.rect(0.24, 0.84, 0.52, 0.06, a.ink, radius: 0.03);
    a.shape([(0.3, 0.16), (0.7, 0.16), (0.5, 0.5)], a.stock);
    a.shape([(0.5, 0.5), (0.7, 0.84), (0.3, 0.84)], a.accent);
  },
  'Digitales/Datenschutz': (a) {
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        a.circle(0.1 + i * 0.07, 0.2 + j * 0.07, 0.018, a.ink);
      }
    }
    a.canvas.drawArc(
      Rect.fromCircle(center: a.p(0.5, 0.44), radius: a.d(0.16)),
      pi,
      pi,
      false,
      a.stroke(a.ink, 0.06),
    );
    a.rect(0.28, 0.44, 0.44, 0.4, a.stock, radius: 0.06);
    a.circle(0.5, 0.6, 0.05, a.ink);
    a.rect(0.48, 0.6, 0.04, 0.12, a.ink);
  },
  'Sicherheit': (a) {
    Path shield(double inset) {
      final o = a.p(0.5, 0.12 + inset);
      final path = Path()..moveTo(o.dx, o.dy);
      for (final (x, y) in [
        (0.8 - inset, 0.24 + inset),
        (0.78 - inset, 0.58),
      ]) {
        final q = a.p(x, y);
        path.lineTo(q.dx, q.dy);
      }
      final c1 = a.p(0.74 - inset, 0.78 - inset / 2);
      final tip = a.p(0.5, 0.9 - inset);
      final c2 = a.p(0.26 + inset, 0.78 - inset / 2);
      final left = a.p(0.22 + inset, 0.58);
      final top = a.p(0.2 + inset, 0.24 + inset);
      path
        ..quadraticBezierTo(c1.dx, c1.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(c2.dx, c2.dy, left.dx, left.dy)
        ..lineTo(top.dx, top.dy)
        ..close();
      return path;
    }

    a.canvas.drawPath(shield(0), a.fill(a.stock));
    a.canvas.drawPath(shield(0.1), a.fill(a.ink));
    a.circle(0.5, 0.48, 0.07, a.accent);
  },
  'Migration/Integration': (a) {
    final left = Path()
      ..addOval(Rect.fromCircle(center: a.p(0.37, 0.5), radius: a.d(0.25)));
    final right = Path()
      ..addOval(Rect.fromCircle(center: a.p(0.63, 0.5), radius: a.d(0.25)));
    a.canvas.drawPath(left, a.fill(a.stock));
    a.canvas.drawPath(right, a.fill(a.accent));
    a.canvas.drawPath(
      Path.combine(PathOperation.intersect, left, right),
      a.fill(a.ink),
    );
  },
  'Außenpolitik/Verteidigung': (a) {
    a.circle(0.5, 0.5, 0.35, a.stock);
    final globe = Rect.fromCircle(center: a.p(0.5, 0.5), radius: a.d(0.35));
    a.canvas.drawOval(
      Rect.fromCenter(
        center: globe.center,
        width: globe.width * 0.46,
        height: globe.height,
      ),
      a.stroke(a.ink, 0.03),
    );
    a.line(0.15, 0.5, 0.85, 0.5, a.ink, 0.03);
    a.line(0.22, 0.32, 0.78, 0.32, a.ink, 0.025);
    a.line(0.22, 0.68, 0.78, 0.68, a.ink, 0.025);
    a.circle(0.82, 0.18, 0.07, a.accent);
  },
  'Demokratie/Mitbestimmung': (a) {
    a.ground(0.9, a.ink);
    for (final (x, color) in [
      (0.26, a.ink),
      (0.74, a.ink),
      (0.5, a.stock),
    ]) {
      final top = x == 0.5 ? 0.3 : 0.42;
      a.circle(x, top, 0.08, color);
      a.rect(
        x - 0.13,
        top + 0.12,
        0.26,
        0.9 - top - 0.12,
        color,
        radius: 0.12,
      );
    }
    a.rect(0.62, 0.08, 0.26, 0.16, a.accent, radius: 0.06);
  },
  'Stadtentwicklung/Bauen': (a) {
    a.ground(0.9, a.ink);
    a.rect(0.1, 0.52, 0.18, 0.38, a.stock);
    a.rect(0.3, 0.3, 0.16, 0.6, a.ink);
    a.rect(0.48, 0.46, 0.16, 0.44, a.accent);
    a.rect(0.66, 0.38, 0.2, 0.52, a.stock);
    a.line(0.82, 0.08, 0.82, 0.38, a.ink, 0.03);
    a.line(0.56, 0.1, 0.95, 0.1, a.ink, 0.03);
  },
  'Gesundheit/Pflege': (a) {
    a.rect(0.4, 0.18, 0.2, 0.64, a.stock, radius: 0.05);
    a.rect(0.18, 0.4, 0.64, 0.2, a.stock, radius: 0.05);
    a.circle(0.5, 0.5, 0.06, a.ink);
    a.circle(0.8, 0.18, 0.07, a.accent);
  },
  // Children in the shade of a big tree on a sunny day.
  'Familie/Kinder': (a) {
    a.circle(0.78, 0.22, 0.13, a.accent);
    a.circle(0.34, 1.04, 0.46, a.ink);
    a.circle(0.24, 0.8, 0.08, a.stock);
    a.circle(0.44, 0.84, 0.06, a.stock);
  },
  'Umwelt/Natur': (a) {
    a.ground(0.88, a.ink);
    a.rect(0.46, 0.56, 0.08, 0.32, a.ink);
    a.circle(0.5, 0.42, 0.24, a.stock);
    a.circle(0.82, 0.2, 0.07, a.accent);
  },
  'Selbstständigkeit/Unternehmertum': (a) {
    for (final (i, h) in [0.24, 0.44, 0.64].indexed) {
      a.rect(
        0.14 + i * 0.24,
        0.88 - h,
        0.2,
        h,
        i.isOdd ? a.ink : a.stock,
        radius: 0.03,
      );
    }
    a.circle(0.72, 0.14, 0.08, a.accent);
  },
  'Gleichstellung/Inklusion': (a) {
    a.circle(0.34, 0.24, 0.08, a.stock);
    a.circle(0.66, 0.24, 0.08, a.accent);
    a.rect(0.18, 0.42, 0.64, 0.1, a.ink, radius: 0.05);
    a.rect(0.18, 0.6, 0.64, 0.1, a.ink, radius: 0.05);
  },
};

/// Every topic with its own picture, for tests.
Iterable<String> get topicsWithArt => _recipes.keys;
