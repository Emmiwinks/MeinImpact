import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/mi_theme.dart';

/// One pot of the Stadthaushalt: a budget area (backend GELD_BEREICHE, the
/// keys of `GeldEffekt.bereich`) with its label and glyph.
class HaushaltTopf {
  const HaushaltTopf(this.id, this.label, this.icon);

  final String id;

  /// With non-breaking spaces after "&", so a line never starts with it.
  final String label;
  final IconData icon;
}

const haushaltToepfe = [
  HaushaltTopf('kinder_bildung', 'Kitas & Schulen', Icons.menu_book_rounded),
  // "Gesundheit" needs a line of its own in a narrow pot.
  HaushaltTopf(
    'soziales',
    'Soziales, Pflege & Gesundheit',
    Icons.favorite_rounded,
  ),
  HaushaltTopf('oepnv_rad', 'Bus, Bahn & Rad', Icons.directions_bus_rounded),
  HaushaltTopf('strassen', 'Straßen & Brücken', Icons.construction_rounded),
  HaushaltTopf('kultur', 'Kultur', Icons.music_note_rounded),
  HaushaltTopf(
    'sport_freizeit',
    'Sport, Bäder & Freizeit',
    Icons.sports_soccer_rounded,
  ),
  HaushaltTopf('sicherheit', 'Sicherheit & Ordnung', Icons.shield_rounded),
  HaushaltTopf('gruen_klima', 'Grün, Umwelt & Klima', Icons.eco_rounded),
];

/// How many Taler the Stadtkasse holds.
const haushaltTaler = 20;

/// The label as one plain line, for screen readers.
String topfName(HaushaltTopf topf) => topf.label.replaceAll(' ', ' ');

/// A pot's colour, by its place in the list like the topics (the Rotating
/// Suit Rule: never by meaning).
Color topfColor(BuildContext context, int index) =>
    context.mi.topics[index % context.mi.topics.length];

abstract final class _Taler {
  static const face = Color(0xFFFFBF3C);
  static const rim = Color(0xFFD9961A);
  static const edge = Color(0xFFB87A12);
  static const ink = Color(0xFF101820);
}

/// A Taler seen from above: a rim, a ring and a dot, no number, so it
/// stands for no real amount.
void paintTalerTop(Canvas canvas, Offset c, double r) {
  canvas
    ..drawCircle(c, r, Paint()..color = _Taler.rim)
    ..drawCircle(c, r * 0.86, Paint()..color = _Taler.face)
    ..drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1
        ..color = _Taler.ink.withValues(alpha: 0.25),
    )
    ..drawCircle(
      c,
      r * 0.2,
      Paint()..color = _Taler.ink.withValues(alpha: 0.3),
    );
}

/// A Taler seen from the side, lying in a stack: its top face at [y] and an
/// edge [thick] deep below it.
void paintTalerSide(
  Canvas canvas,
  double cx,
  double y,
  double rx,
  double ry,
  double thick,
) {
  final top =
      Rect.fromCenter(center: Offset(cx, y), width: rx * 2, height: ry * 2);
  canvas
    ..drawOval(top.shift(Offset(0, thick)), Paint()..color = _Taler.edge)
    ..drawRect(
      Rect.fromLTRB(cx - rx, y, cx + rx, y + thick),
      Paint()..color = _Taler.rim,
    )
    ..drawOval(top, Paint()..color = _Taler.face)
    ..drawOval(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _Taler.rim,
    );
}

/// Draws [icon] in ink, centred on [c].
void paintGlyph(Canvas canvas, IconData icon, Offset c, double size) {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        color: _Taler.ink,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, c - Offset(painter.width / 2, painter.height / 2));
}

/// Three Taler, for the intro's preview.
class TalerHaeufchen extends StatelessWidget {
  const TalerHaeufchen({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _HaeufchenPainter(), size: Size.infinite);
}

class _HaeufchenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 76;
    canvas.scale(s);
    paintTalerTop(canvas, const Offset(27, 47), 16);
    paintTalerTop(canvas, const Offset(50, 50), 16);
    paintTalerTop(canvas, const Offset(38, 27), 16);
  }

  @override
  bool shouldRepaint(_HaeufchenPainter old) => false;
}

/// A pot as a glass jar: a lid in the pot's colour, a sticker with its
/// glyph, and the Taler stacked inside. Drawn on a 72 × 110 sheet.
class TopfGlas extends StatelessWidget {
  const TopfGlas({
    required this.color,
    required this.icon,
    required this.taler,
    this.width = 72,
    super.key,
  });

  final Color color;
  final IconData icon;
  final int taler;
  final double width;

  static const sheet = Size(72, 110);

  /// Where the next Taler lands, on the sheet.
  static Offset landing(int taler) =>
      Offset(36, _stackBase - math.min(taler, haushaltTaler) * _step);

  static const _stackBase = 100.0;
  static const _step = 5.2;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      size: Size(width, width * sheet.height / sheet.width),
      painter: _GlasPainter(
        color: color,
        icon: icon,
        taler: taler,
        glass: dark
            ? const Color(0x12F4F1EA)
            : Colors.white.withValues(alpha: 0.55),
        glassEdge: dark ? const Color(0x61F4F1EA) : const Color(0x4D101820),
      ),
    );
  }
}

class _GlasPainter extends CustomPainter {
  _GlasPainter({
    required this.color,
    required this.icon,
    required this.taler,
    required this.glass,
    required this.glassEdge,
  });

  final Color color;
  final IconData icon;
  final int taler;
  final Color glass;
  final Color glassEdge;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / TopfGlas.sheet.width);
    final body = RRect.fromLTRBR(4, 16, 68, 108, const Radius.circular(16));
    canvas
      ..drawRRect(
        RRect.fromLTRBR(12, 0, 60, 13, const Radius.circular(5)),
        Paint()..color = color,
      )
      ..drawRRect(
        RRect.fromLTRBR(16, 11, 56, 19, const Radius.circular(2)),
        Paint()..color = glassEdge.withValues(alpha: glassEdge.a * 0.6),
      )
      ..drawRRect(body, Paint()..color = glass)
      ..save()
      ..clipRRect(body);
    for (var k = 0; k < taler; k++) {
      paintTalerSide(
        canvas,
        36,
        TopfGlas._stackBase - k * TopfGlas._step,
        25,
        5,
        2.4,
      );
    }
    canvas
      ..restore()
      ..drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = glassEdge,
      )
      // The glass catches the light on its left.
      ..drawLine(
        const Offset(12, 34),
        const Offset(12, 78),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(const Offset(36, 40), 13, Paint()..color = color);
    paintGlyph(canvas, icon, const Offset(36, 40), 16);
  }

  @override
  bool shouldRepaint(_GlasPainter old) =>
      old.taler != taler ||
      old.color != color ||
      old.glass != glass ||
      old.glassEdge != glassEdge;
}

/// "Dein Stadthaushalt": the pots as Taler stacks side by side on a sheet
/// of card stock, each above its sticker. The fullest stack reaches the
/// top; the Taler grow thicker rather than float apart.
class StadthaushaltBild extends StatelessWidget {
  const StadthaushaltBild({required this.taler, super.key});

  /// Taler per pot id.
  final Map<String, int> taler;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 236 / 206,
      child: CustomPaint(
        painter: _BildPainter(
          counts: [for (final t in haushaltToepfe) taler[t.id] ?? 0],
          colors: [
            for (var i = 0; i < haushaltToepfe.length; i++)
              topfColor(context, i),
          ],
        ),
      ),
    );
  }
}

class _BildPainter extends CustomPainter {
  _BildPainter({required this.counts, required this.colors});

  final List<int> counts;
  final List<Color> colors;

  static const _sheet = Size(236, 206);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..scale(size.width / _sheet.width)
      ..drawRect(Offset.zero & _sheet, Paint()..color = const Color(0xFFF4F1EA))
      ..drawLine(
        const Offset(6, 156),
        const Offset(230, 156),
        Paint()
          ..color = _Taler.ink.withValues(alpha: 0.18)
          ..strokeWidth = 2,
      );
    final most = counts.fold(1, math.max);
    final step = math.min(10.0, 120 / most);
    final thick = step - 1;
    for (var i = 0; i < counts.length; i++) {
      final x = 18 + i * 28.6;
      for (var k = 0; k < counts[i]; k++) {
        paintTalerSide(canvas, x, 152 - thick - k * step, 12, 3.6, thick);
      }
      canvas.drawCircle(Offset(x, 184), 10.5, Paint()..color = colors[i]);
      paintGlyph(canvas, haushaltToepfe[i].icon, Offset(x, 184), 13);
    }
  }

  @override
  bool shouldRepaint(_BildPainter old) =>
      !_same(old.counts, counts) || !_same(old.colors, colors);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
