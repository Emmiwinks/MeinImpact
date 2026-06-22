import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Palette ───────────────────────────────────────────────────────────────────

const _bg = Color(0xFF080F1E);
const _green = Color(0xFF22C55E);
const _amber = Color(0xFFF59E0B);
const _text = Color(0xFFF1F5F9);
const _sub = Color(0xFF94A3B8);
const _muted = Color(0xFF64748B);
const _card = Color(0x0DFFFFFF);
const _border = Color(0x17FFFFFF);

const _kButterflyColors = [
  Color(0xFFF97316),
  Color(0xFFEC4899),
  Color(0xFFA855F7),
  Color(0xFF06B6D4),
  Color(0xFF22C55E),
  Color(0xFFEAB308),
  Color(0xFFF43F5E),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFFFB923C),
  Color(0xFFE879F9),
  Color(0xFF38BDF8),
  Color(0xFF84CC16),
  Color(0xFFF59E0B),
];

// ── Root screen ───────────────────────────────────────────────────────────────

class LandingScreen extends StatefulWidget {
  const LandingScreen({required this.onStart, super.key});

  final VoidCallback onStart;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _megaphoneKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Nav(),
                _Hero(megaphoneKey: _megaphoneKey),
                const _Features(),
                const _Contact(),
                const _Footer(),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: _ButterflyOverlay(megaphoneKey: _megaphoneKey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Nav ───────────────────────────────────────────────────────────────────────

class _Nav extends StatelessWidget {
  const _Nav();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _text,
                letterSpacing: -0.4,
              ),
              children: [
                TextSpan(text: 'mein'),
                TextSpan(text: 'Impact', style: TextStyle(color: _green)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x1FF59E0B),
              border: Border.all(color: const Color(0x59F59E0B)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'IM AUFBAU',
              style: TextStyle(
                color: Color(0xFFFCD34D),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.megaphoneKey});

  final GlobalKey megaphoneKey;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: w < 600 ? 24 : 48,
        vertical: 64,
      ),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.2,
          colors: [Color(0x0E22C55E), _bg],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _MegaphoneIcon(megaphoneKey: megaphoneKey),
          const SizedBox(height: 48),
          Text(
            'Deine Stimme.\nDein Impact.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w < 600 ? 36 : 52,
              fontWeight: FontWeight.w800,
              color: _text,
              height: 1.08,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'MeinImpact macht politisches Engagement einfach\n'
            'und wirkungsvoll — für alle, die etwas verändern wollen.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: _sub, height: 1.7),
          ),
          const SizedBox(height: 44),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x40F59E0B)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              '🚧  Bald verfügbar',
              style: TextStyle(
                color: Color(0xFFFCD34D),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MegaphoneIcon extends StatelessWidget {
  const _MegaphoneIcon({required this.megaphoneKey});

  final GlobalKey megaphoneKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: megaphoneKey,
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _amber.withValues(alpha: 0.18),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('📣', style: TextStyle(fontSize: 44)),
    );
  }
}

// ── Features ──────────────────────────────────────────────────────────────────

class _Features extends StatelessWidget {
  const _Features();

  static const _cards = [
    (
      icon: '🏛️',
      title: 'Politische Aktionen',
      body: 'Entdecke Aktionen auf Bundes-, Landes- und Regionalebene, '
          'die zu deinen Werten passen.',
    ),
    (
      icon: '🧭',
      title: 'Dein Werteprofil',
      body: 'Finde heraus, welche Themen relevant sind und welchen Effekt '
          'politische Entscheidungen auf deinen Alltag haben.',
    ),
    (
      icon: '📰',
      title: 'Tracke deinen Impact',
      body: 'Nach einer Aktion bleibst du informiert — wie Abgeordnete '
          'gestimmt haben und was entschieden wurde.',
    ),
    (
      icon: '✉️',
      title: 'Briefe an Abgeordnete',
      body: 'Schreibe mit KI-Unterstützung wirkungsvolle Briefe '
          'direkt an deine Volksvertreter.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w < 600 ? 24 : 48,
        vertical: 80,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WAS DICH ERWARTET',
            style: TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Demokratie,\nneu gedacht.',
            style: TextStyle(
              color: _text,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1.12,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'MeinImpact verbindet dich mit politischen Aktionen, die zu deinen Werten passen. '
            'Dein wöchentlicher Beitrag zur Demokratie in drei Minuten.',
            style: TextStyle(color: _sub, fontSize: 16, height: 1.72),
          ),
          const SizedBox(height: 40),
          GridView.count(
            crossAxisCount: w < 600 ? 1 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: w < 600 ? 3.2 : 1.6,
            children: _cards
                .map(
                  (c) =>
                      _FeatureCard(icon: c.icon, title: c.title, body: c.body),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              body,
              style: const TextStyle(color: _sub, fontSize: 13, height: 1.6),
              overflow: TextOverflow.fade,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Contact ───────────────────────────────────────────────────────────────────

class _Contact extends StatelessWidget {
  const _Contact();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w < 600 ? 24 : 48,
        vertical: 80,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        children: [
          const Text(
            'KONTAKT',
            style: TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Meld dich bei uns!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Fragen, Feedback oder Interesse am Beta-Test?\n'
            'Wir freuen uns über jede Nachricht.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _sub, fontSize: 16, height: 1.7),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse('mailto:hallo@meinimpact.de')),
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('hallo@meinimpact.de'),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: const Color(0xFF052E16),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: const Text(
        '© 2025 MeinImpact · Impressum · Datenschutz',
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 12),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Butterfly animation
// ══════════════════════════════════════════════════════════════════════════════

class _BfData {
  _BfData({
    required this.x,
    required this.y,
    required this.color,
    required this.scale,
    required this.flapPeriodMs,
    required this.spawnDelayMs,
  })  : sx = x,
        sy = y,
        tx = x,
        ty = y;

  // Position
  double x, y;
  // Current bezier flight
  double sx, sy, tx, ty;
  double cp1x = 0, cp1y = 0, cp2x = 0, cp2y = 0;
  double durMs = 1000;
  double? flightStartMs;
  // Visual
  double tilt = 0; // degrees, clamped ±28
  double elapsedMs = 0; // for wing flap phase
  final Color color;
  final double scale;
  final double flapPeriodMs;
  final double spawnDelayMs;
  bool visible = false;
}

// notifyListeners() is protected — subclass so we can call it from the state.
class _Repaint extends ChangeNotifier {
  void tick() => notifyListeners();
}

// ── Overlay widget ────────────────────────────────────────────────────────────

class _ButterflyOverlay extends StatefulWidget {
  const _ButterflyOverlay({required this.megaphoneKey});

  final GlobalKey megaphoneKey;

  @override
  State<_ButterflyOverlay> createState() => _ButterflyOverlayState();
}

class _ButterflyOverlayState extends State<_ButterflyOverlay>
    with SingleTickerProviderStateMixin {
  late final _ticker = createTicker(_onTick);
  final _repaint = _Repaint();
  final _rng = Random();
  final List<_BfData> _bflies = [];

  Offset _spawn = Offset.zero;
  Size _screen = Size.zero;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _init() {
    if (!mounted) return;
    final box =
        widget.megaphoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    // The 📣 emoji's output end is the right side of the icon circle.
    final center = box.localToGlobal(box.size.center(Offset.zero));
    _spawn = Offset(center.dx + 42, center.dy - 4);
    _screen = MediaQuery.of(context).size;

    for (var i = 0; i < 14; i++) {
      final b = _BfData(
        x: _spawn.dx,
        y: _spawn.dy,
        color: _kButterflyColors[i % _kButterflyColors.length],
        scale: 0.55 + _rng.nextDouble() * 0.5,
        flapPeriodMs: 600 + _rng.nextDouble() * 300,
        spawnDelayMs: i * 260.0 + _rng.nextDouble() * 350,
      );
      _startFlight(b, isFirst: true);
      _bflies.add(b);
    }
    _ready = true;
  }

  void _startFlight(_BfData b, {required bool isFirst}) {
    b.sx = b.x;
    b.sy = b.y;

    final Offset target;
    if (isFirst) {
      final angle = (_rng.nextDouble() - 0.5) * pi * 1.6;
      final dist = 130 + _rng.nextDouble() * 240;
      target = Offset(
        (_spawn.dx + cos(angle) * dist).clamp(40, _screen.width - 40),
        (_spawn.dy + sin(angle) * dist).clamp(60, _screen.height - 60),
      );
    } else {
      target = Offset(
        50 + _rng.nextDouble() * (_screen.width - 100),
        70 + _rng.nextDouble() * (_screen.height - 140),
      );
    }

    b.tx = target.dx;
    b.ty = target.dy;

    final mx = (b.sx + b.tx) / 2;
    final my = (b.sy + b.ty) / 2;
    final perpX = -(b.ty - b.sy) * 0.45;
    final perpY = (b.tx - b.sx) * 0.45;
    final jitter = isFirst ? 80.0 : 130.0;

    b.cp1x = mx + perpX + (_rng.nextDouble() - 0.5) * jitter;
    b.cp1y = my + perpY + (_rng.nextDouble() - 0.5) * jitter;
    b.cp2x = mx - perpX * 0.6 + (_rng.nextDouble() - 0.5) * jitter * 0.7;
    b.cp2y = my - perpY * 0.6 + (_rng.nextDouble() - 0.5) * jitter * 0.7;
    b.durMs = isFirst
        ? 1800 + _rng.nextDouble() * 1200
        : 5500 + _rng.nextDouble() * 5000;
    b.flightStartMs = null;
  }

  void _onTick(Duration elapsed) {
    if (!_ready) return;
    final ms = elapsed.inMicroseconds / 1000.0;

    for (final b in _bflies) {
      if (ms < b.spawnDelayMs) continue;

      if (!b.visible) {
        b.visible = true;
        b.flightStartMs = ms;
      }

      b.elapsedMs = ms;

      final fs = b.flightStartMs ?? ms;
      final raw = ((ms - fs) / b.durMs).clamp(0.0, 1.0);
      final e = _eio(raw);

      final nx = _cubic(e, b.sx, b.cp1x, b.cp2x, b.tx);
      final ny = _cubic(e, b.sy, b.cp1y, b.cp2y, b.ty);
      final dx = nx - b.x;
      final dy = ny - b.y;
      if (dx.abs() > 0.05 || dy.abs() > 0.05) {
        b.tilt = (atan2(dy, dx) * (180 / pi)).clamp(-28.0, 28.0);
      }
      b.x = nx;
      b.y = ny;

      if (raw >= 1.0) {
        _startFlight(b, isFirst: false);
        b.flightStartMs = ms;
      }
    }

    _repaint.tick();
  }

  static double _cubic(double t, double p0, double c1, double c2, double p1) {
    final m = 1 - t;
    return m * m * m * p0 +
        3 * m * m * t * c1 +
        3 * m * t * t * c2 +
        t * t * t * p1;
  }

  static double _eio(double t) =>
      t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2).toDouble() / 2;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ButterflyPainter(_bflies, repaint: _repaint),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _ButterflyPainter extends CustomPainter {
  _ButterflyPainter(this.bflies, {required Listenable repaint})
      : super(repaint: repaint);

  final List<_BfData> bflies;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bflies) {
      if (!b.visible) continue;
      _draw(canvas, b);
    }
  }

  void _draw(Canvas canvas, _BfData b) {
    canvas.save();
    canvas.translate(b.x, b.y);
    canvas.rotate(b.tilt * pi / 180);

    // Wing flap: scaleX oscillates 1.0 → 0.22 like the original CSS animation.
    final phase = (b.elapsedMs % b.flapPeriodMs) / b.flapPeriodMs;
    final flapX = 0.22 + 0.78 * (0.5 + 0.5 * cos(phase * 2 * pi));

    canvas.scale(b.scale * flapX, b.scale);
    // SVG viewBox is 34×30; centre of butterfly body is at (17, 15).
    canvas.translate(-17, -15);

    _paintWings(canvas, b.color);
    canvas.restore();
  }

  static void _paintWings(Canvas canvas, Color color) {
    const bodyColor = Color(0xFF1A1A2E);
    final main = Paint()..color = color.withValues(alpha: 0.72);
    final dim = Paint()..color = color.withValues(alpha: 0.54); // 0.72 * 0.75
    final body = Paint()..color = bodyColor;
    final antenna = Paint()
      ..color = bodyColor
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Upper-left wing
    canvas.drawPath(
      Path()
        ..moveTo(17, 15)
        ..quadraticBezierTo(10, 2, 1, 4)
        ..quadraticBezierTo(-1, 15, 17, 15),
      main,
    );
    // Upper-right wing
    canvas.drawPath(
      Path()
        ..moveTo(17, 15)
        ..quadraticBezierTo(24, 2, 33, 4)
        ..quadraticBezierTo(35, 15, 17, 15),
      main,
    );
    // Lower-left wing
    canvas.drawPath(
      Path()
        ..moveTo(17, 15)
        ..quadraticBezierTo(7, 27, 1, 24)
        ..quadraticBezierTo(3, 15, 17, 15),
      dim,
    );
    // Lower-right wing
    canvas.drawPath(
      Path()
        ..moveTo(17, 15)
        ..quadraticBezierTo(27, 27, 33, 24)
        ..quadraticBezierTo(31, 15, 17, 15),
      dim,
    );
    // Body
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(17, 15), width: 4, height: 14),
      body,
    );
    // Head
    canvas.drawCircle(const Offset(17, 8), 2.2, body);
    // Left antenna
    canvas.drawLine(const Offset(17, 7), const Offset(12, 1), antenna);
    canvas.drawCircle(const Offset(12, 1), 1.3, body);
    // Right antenna
    canvas.drawLine(const Offset(17, 7), const Offset(22, 1), antenna);
    canvas.drawCircle(const Offset(22, 1), 1.3, body);
  }

  @override
  bool shouldRepaint(_ButterflyPainter old) => false;
}
