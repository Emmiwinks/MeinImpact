import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../app/theme/mi_theme.dart';
import '../../feed/presentation/widgets/werte_bild.dart';
import 'stadthaushalt.dart';

// How long a Taler takes from the Stadtkasse into a pot, or back.
const _kFlight = Duration(milliseconds: 420);

/// "Wohin mit dem Geld deiner Stadt?": the Stadtkasse holds 20 Taler, and
/// tapping one of the eight pots drops one in; "−" under a pot puts one
/// back. "Fertig" only once all are spent, then the stacks settle into a
/// framed picture, "Dein Stadthaushalt". Required in onboarding: there is
/// no way to skip it.
class StadthaushaltScreen extends StatefulWidget {
  const StadthaushaltScreen({
    required this.onComplete,
    this.initial = const {},
    this.onBack,
    super.key,
  });

  /// Taler per pot id, summing to [haushaltTaler].
  final void Function(Map<String, int> taler) onComplete;

  /// An earlier distribution to start from ("Neu verteilen").
  final Map<String, int> initial;

  /// System Back outside the reveal: back to the previous onboarding step,
  /// or out to the profile without saving. Null lets the route pop.
  final VoidCallback? onBack;

  @override
  State<StadthaushaltScreen> createState() => _StadthaushaltScreenState();
}

class _Flight {
  _Flight({
    required this.from,
    required this.to,
    required this.controller,
    required this.pot,
    required this.intoPot,
  });

  final Offset from;
  final Offset to;
  final AnimationController controller;
  final int pot;
  final bool intoPot;
}

class _StadthaushaltScreenState extends State<StadthaushaltScreen>
    with TickerProviderStateMixin {
  late final List<int> _taler = _start();
  final _stack = GlobalKey();
  final _kasse = GlobalKey();
  late final _jars = [for (final _ in haushaltToepfe) GlobalKey()];
  final _flights = <_Flight>[];
  bool _revealing = false;

  // Only a full, valid distribution is picked up again.
  List<int> _start() {
    final counts = [for (final t in haushaltToepfe) widget.initial[t.id] ?? 0];
    final sum = counts.fold(0, (a, b) => a + b);
    return sum == haushaltTaler && counts.every((c) => c >= 0)
        ? counts
        : List.filled(haushaltToepfe.length, 0);
  }

  int get _left => haushaltTaler - _taler.fold(0, (a, b) => a + b);

  // Taler in flight are not drawn where they are headed until they land.
  int _incoming(int pot) =>
      _flights.where((f) => f.intoPot && f.pot == pot).length;
  int get _returning => _flights.where((f) => !f.intoPot).length;

  @override
  void dispose() {
    for (final f in _flights) {
      f.controller.dispose();
    }
    super.dispose();
  }

  void _add(int pot) {
    if (_left == 0) return;
    final from = _kasseSlot(_left - 1);
    final to = _jarTop(pot);
    setState(() => _taler[pot]++);
    _fly(pot, from, to, intoPot: true);
  }

  void _remove(int pot) {
    if (_taler[pot] == 0) return;
    final from = _jarTop(pot);
    setState(() => _taler[pot]--);
    _fly(pot, from, _kasseSlot(_left - 1), intoPot: false);
  }

  void _fly(int pot, Offset? from, Offset? to, {required bool intoPot}) {
    if (from == null || to == null || MiMotion.reduced(context)) return;
    final controller = AnimationController(vsync: this, duration: _kFlight);
    final flight = _Flight(
      from: from,
      to: to,
      controller: controller,
      pot: pot,
      intoPot: intoPot,
    );
    setState(() => _flights.add(flight));
    controller.forward().whenComplete(() {
      if (!mounted) return;
      setState(() => _flights.remove(flight));
      controller.dispose();
    });
  }

  Offset? _local(GlobalKey key, Offset offset) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null) return null;
    return stack.globalToLocal(box.localToGlobal(offset));
  }

  // The centre of the [index]th coin place in the Stadtkasse.
  Offset? _kasseSlot(int index) {
    final box = _kasse.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final cell = box.size.width / _KassePainter.perRow;
    return _local(
      _kasse,
      Offset(
        (index % _KassePainter.perRow + 0.5) * cell,
        (index ~/ _KassePainter.perRow + 0.5) * cell,
      ),
    );
  }

  // Where a Taler enters a jar: just above its stack.
  Offset? _jarTop(int pot) {
    final box = _jars[pot].currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final scale = box.size.width / TopfGlas.sheet.width;
    return _local(_jars[pot], TopfGlas.landing(_taler[pot]) * scale);
  }

  void _back() {
    if (_revealing) {
      setState(() => _revealing = false);
    } else {
      widget.onBack?.call();
    }
  }

  void _done() => widget.onComplete({
        for (var i = 0; i < haushaltToepfe.length; i++)
          if (_taler[i] > 0) haushaltToepfe[i].id: _taler[i],
      });

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return PopScope(
      canPop: !_revealing && widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: colors.table,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration:
                MiMotion.reduced(context) ? Duration.zero : MiMotion.settle,
            child: _revealing ? _result(context) : _distribute(context),
          ),
        ),
      ),
    );
  }

  Widget _distribute(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Stack(
      key: _stack,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  MiSpace.lg,
                  MiSpace.lg,
                  MiSpace.lg,
                  MiSpace.base,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Wohin mit dem Geld deiner Stadt?',
                      style: text.titleLarge,
                    ),
                    const SizedBox(height: MiSpace.sm),
                    Text(
                      'Entscheide aus dem Bauch heraus. Du kannst deine '
                      'Angaben jederzeit ändern.',
                      style:
                          text.bodyMedium?.copyWith(color: colors.onTableMuted),
                    ),
                    const SizedBox(height: MiSpace.base + 2),
                    _Kasse(
                      paintKey: _kasse,
                      shown: _left - _returning,
                      left: _left,
                    ),
                    const SizedBox(height: MiSpace.base + 4),
                    for (final row in [0, 4]) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = row; i < row + 4; i++) ...[
                            if (i > row) const SizedBox(width: 6),
                            Expanded(
                              child: _Topf(
                                index: i,
                                glassKey: _jars[i],
                                taler: _taler[i],
                                shown: _taler[i] - _incoming(i),
                                onAdd: _left > 0 ? () => _add(i) : null,
                                onRemove: () => _remove(i),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (row == 0) const SizedBox(height: MiSpace.md),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MiSpace.lg,
                MiSpace.sm,
                MiSpace.lg,
                MiSpace.base,
              ),
              child: FilledButton(
                onPressed:
                    _left == 0 ? () => setState(() => _revealing = true) : null,
                style: colors.tableButton,
                child: const Text('Fertig'),
              ),
            ),
          ],
        ),
        for (final f in _flights)
          AnimatedBuilder(
            animation: f.controller,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(f.controller.value);
              // A little arc, peaking above the higher end.
              final lift = 36 * 4 * t * (1 - t);
              final p = Offset.lerp(f.from, f.to, t)! - Offset(0, lift);
              final r = lerpDouble(
                f.intoPot ? 13 : 10,
                f.intoPot ? 10 : 13,
                t,
              )!;
              return Positioned(
                left: p.dx - r,
                top: p.dy - r,
                child: IgnorePointer(
                  child: CustomPaint(
                    size: Size.square(r * 2),
                    painter: _FlyingTaler(),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final reduced = MiMotion.reduced(context);
    return Column(
      key: const ValueKey('result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              const framing = (WerteBildRahmen.frame + WerteBildRahmen.mat) * 2;
              final width = math.min(
                math.min(300.0, box.maxWidth - MiSpace.lg * 2 - framing),
                (box.maxHeight - 120 - framing) * 236 / 206,
              );
              return Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduced ? 1 : 0, end: 1),
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 900),
                  curve: MiMotion.ease,
                  builder: (context, t, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        image: true,
                        label: 'Dein Stadthaushalt: ${_reading()}',
                        excludeSemantics: true,
                        child: WerteBildRahmen(
                          t: t,
                          child: SizedBox(
                            width: math.max(120, width),
                            child: StadthaushaltBild(taler: _counts()),
                          ),
                        ),
                      ),
                      const SizedBox(height: MiSpace.lg),
                      Opacity(
                        opacity: Curves.easeIn.transform(t),
                        child: Text(
                          'Dein Stadthaushalt',
                          style: text.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MiSpace.lg,
            MiSpace.sm,
            MiSpace.lg,
            MiSpace.base,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _done,
                style: colors.tableButton,
                child: const Text('Weiter'),
              ),
              const SizedBox(height: MiSpace.sm),
              OutlinedButton(
                onPressed: () => setState(() => _revealing = false),
                child: const Text('Neu verteilen'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, int> _counts() => {
        for (var i = 0; i < haushaltToepfe.length; i++)
          haushaltToepfe[i].id: _taler[i],
      };

  String _reading() => [
        for (var i = 0; i < haushaltToepfe.length; i++)
          '${topfName(haushaltToepfe[i])} ${_taler[i]}',
      ].join(', ');
}

/// The Stadtkasse: what is left to spend, and a place for every Taler.
class _Kasse extends StatelessWidget {
  const _Kasse({
    required this.paintKey,
    required this.shown,
    required this.left,
  });

  final GlobalKey paintKey;

  /// Coins drawn in the tray: those left, less those still flying back.
  final int shown;
  final int left;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: left > 0
          ? 'Stadtkasse: noch $left von $haushaltTaler Talern'
          : 'Stadtkasse: alle Taler verteilt',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: colors.tableRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.keyline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    'Stadtkasse',
                    style:
                        text.labelMedium?.copyWith(color: colors.onTableMuted),
                  ),
                ),
                Text(
                  left > 0 ? 'Noch $left Taler' : 'Alles verteilt',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio:
                  _KassePainter.perRow / (haushaltTaler / _KassePainter.perRow),
              child: CustomPaint(
                key: paintKey,
                painter: _KassePainter(shown: shown, dent: colors.onTableMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KassePainter extends CustomPainter {
  _KassePainter({required this.shown, required this.dent});

  final int shown;
  final Color dent;

  static const perRow = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / perRow;
    final r = cell * 0.44;
    final empty = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = dent.withValues(alpha: 0.4);
    for (var k = 0; k < haushaltTaler; k++) {
      final c = Offset((k % perRow + 0.5) * cell, (k ~/ perRow + 0.5) * cell);
      if (k < shown) {
        paintTalerTop(canvas, c, r);
      } else {
        _dashedCircle(canvas, c, r - 1, empty);
      }
    }
  }

  static void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const dashes = 12;
    const sweep = math.pi * 2 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        i * sweep,
        sweep * 0.5,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_KassePainter old) =>
      old.shown != shown || old.dent != dent;
}

class _FlyingTaler extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintTalerTop(canvas, size.center(Offset.zero), size.width / 2);

  @override
  bool shouldRepaint(_FlyingTaler old) => false;
}

/// One pot: the jar (tap drops a Taler in), its label, and its count with
/// "−" to put one back.
class _Topf extends StatelessWidget {
  const _Topf({
    required this.index,
    required this.glassKey,
    required this.taler,
    required this.shown,
    required this.onAdd,
    required this.onRemove,
  });

  final int index;
  final GlobalKey glassKey;
  final int taler;

  /// Taler drawn in the jar (without those still in flight to it).
  final int shown;
  final VoidCallback? onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final topf = haushaltToepfe[index];
    final name = topfName(topf);
    final label = text.labelMedium!;
    // Three lines, so the counts of a row line up.
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(label.fontSize!) * 1.3 * 3;
    return Column(
      children: [
        Semantics(
          button: true,
          enabled: onAdd != null,
          label: '$name: $taler Taler',
          hint: 'Legt einen Taler hinein',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAdd,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: LayoutBuilder(
                builder: (context, box) => TopfGlas(
                  key: glassKey,
                  color: topfColor(context, index),
                  icon: topf.icon,
                  taler: math.max(0, shown),
                  width: math.min(72, box.maxWidth),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: labelHeight,
          child: ExcludeSemantics(
            child: Text(
              topf.label,
              style: label,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: taler == 0
              ? Center(
                  child: ExcludeSemantics(
                    child: Text(
                      '0',
                      style: text.titleMedium?.copyWith(
                        color: colors.onTableMuted,
                      ),
                    ),
                  ),
                )
              : Semantics(
                  button: true,
                  label: 'Einen Taler aus $name zurücklegen',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: onRemove,
                    customBorder: const StadiumBorder(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.onTableMuted,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.remove_rounded,
                            size: 16,
                            color: colors.onTable,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$taler',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
