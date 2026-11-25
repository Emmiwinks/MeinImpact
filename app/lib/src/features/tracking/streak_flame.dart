import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme/mi_theme.dart';
import 'domain/progress.dart';

/// The streak, top right on the Aktionen tab: a flame with the weeks in a
/// row. The fresher the last action, the bigger the flame; paused, it is
/// grey with a wisp of smoke. When an action carries the streak on, the
/// flame hops and the number rolls; one that lights it again sends a spark
/// to its foot first. Tapping it opens the streak's details.
class StreakFlame extends StatefulWidget {
  const StreakFlame({required this.streak, super.key});

  final Streak streak;

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

enum _Event { hop, reignite }

class _StreakFlameState extends State<StreakFlame>
    with TickerProviderStateMixin {
  // Flicker or smoke; runs a few rounds, then the fire rests, so it lives
  // when looked at without animating forever.
  late final _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..addStatusListener(_idleRound);
  late final _event = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  int _idleRounds = 0;
  _Event? _kind;
  late Streak _shown = widget.streak;
  Timer? _wait;

  static const _rounds = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _liven());
  }

  @override
  void didUpdateWidget(StreakFlame old) {
    super.didUpdateWidget(old);
    final before = old.streak;
    final after = widget.streak;
    if (before.weeks == after.weeks &&
        before.flame == after.flame &&
        before.state == after.state) {
      return;
    }
    final kind = !before.burns && after.burns
        ? _Event.reignite
        : after.weeks > before.weeks || after.flame.index > before.flame.index
            ? _Event.hop
            : null;
    if (kind == null) {
      setState(() => _shown = after);
      return;
    }
    // Badges are turned over first; the fire waits until it is seen.
    _wait?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play(kind));
  }

  void _play(_Event kind) {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      _wait = Timer(const Duration(milliseconds: 250), () => _play(kind));
      return;
    }
    setState(() {
      _kind = kind;
      _shown = widget.streak;
    });
    if (MiMotion.reduced(context)) {
      _event.value = 1;
      return;
    }
    _event.forward(from: 0).then((_) => _liven());
  }

  void _liven() {
    if (!mounted || MiMotion.reduced(context)) return;
    if (!_shown.burns && _shown.flame != FlameLevel.smoke) return;
    _idleRounds = 0;
    _idle.forward(from: 0);
  }

  void _idleRound(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (++_idleRounds < _rounds) _idle.forward(from: 0);
  }

  @override
  void dispose() {
    _wait?.cancel();
    _idle.dispose();
    _event.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final weeks = _shown.weeks;
    final burns = _shown.burns;
    return Semantics(
      button: true,
      label: weeks == 0
          ? 'Keine Serie. Details anzeigen'
          : '$weeks ${weeks == 1 ? 'Woche' : 'Wochen'} in Folge. '
              'Details anzeigen',
      child: InkResponse(
        onTap: () {
          _liven();
          showStreakDetails(context, _shown);
        },
        radius: 28,
        child: SizedBox(
          width: 56,
          height: 48,
          child: AnimatedBuilder(
            animation: Listenable.merge([_idle, _event]),
            builder: (context, _) {
              final p = _event.value;
              final kind = _event.isAnimating || p == 1 ? _kind : null;
              // Reignite: the spark flies for the first 45%, then the
              // flame grows out of the wood.
              final spark = kind == _Event.reignite && p < 0.45 && p > 0
                  ? p / 0.45
                  : null;
              final grow = kind == _Event.reignite
                  ? (p < 0.45
                      ? 0.0
                      : Curves.easeOutBack.transform((p - 0.45) / 0.55))
                  : 1.0;
              final hopAt = kind == _Event.reignite ? 0.45 : 0.0;
              final hop = kind != null && p > hopAt && p < 1
                  ? sin(pi * ((p - hopAt) / (1 - hopAt)).clamp(0, 1)) * 0.3
                  : 0.0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 44,
                    height: 44,
                    child: Transform.scale(
                      scale: 1 + hop,
                      alignment: Alignment.bottomCenter,
                      child: CustomPaint(
                        painter: FlamePainter(
                          level: _shown.flame,
                          phase: _idle.value,
                          grow: grow,
                          spark: spark,
                          colors: colors,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _WeeksBadge(weeks: weeks, burns: burns),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The weeks in a small pill; a new number rolls in from below.
class _WeeksBadge extends StatelessWidget {
  const _WeeksBadge({required this.weeks, required this.burns});

  final int weeks;
  final bool burns;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: MiMotion.settle,
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: burns ? colors.topics[2] : colors.tableRaised,
          borderRadius: BorderRadius.circular(MiRadius.chip),
          border: Border.all(color: colors.table, width: 2),
        ),
        alignment: Alignment.center,
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: MiMotion.reduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 360),
            transitionBuilder: (child, animation) {
              final incoming = child.key == ValueKey(weeks);
              return SlideTransition(
                position: Tween(
                  begin: Offset(0, incoming ? 1 : -1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                ),
                child: child,
              );
            },
            child: Text(
              '$weeks',
              key: ValueKey(weeks),
              style: TextStyle(
                fontFamily: MiFonts.text,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: burns ? colors.onCard : colors.onTableMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The streak's details: the fire, weeks in a row, the last weeks and the
/// pause rule.
Future<void> showStreakDetails(BuildContext context, Streak streak) {
  final theme = Theme.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Schließen',
    barrierColor: Colors.black38,
    transitionDuration:
        MiMotion.reduced(context) ? Duration.zero : MiMotion.settle,
    pageBuilder: (_, __, ___) => Theme(
      data: theme,
      child: _StreakDetails(streak: streak),
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        alignment: Alignment.topRight,
        scale: Tween(begin: 0.9, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        child: child,
      ),
    ),
  );
}

class _StreakDetails extends StatefulWidget {
  const _StreakDetails({required this.streak});

  final Streak streak;

  @override
  State<_StreakDetails> createState() => _StreakDetailsState();
}

class _StreakDetailsState extends State<_StreakDetails>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..addStatusListener((status) {
      // A few rounds, then it rests.
      if (status == AnimationStatus.completed && ++_rounds < 4) {
        _idle.forward(from: 0);
      }
    });
  int _rounds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MiMotion.reduced(context)) _idle.forward();
    });
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  String get _title {
    final weeks = widget.streak.weeks;
    if (weeks == 0) return 'Noch keine Flamme';
    return '$weeks ${weeks == 1 ? 'Woche' : 'Wochen'} in Folge';
  }

  // Nothing to add while the flame burns this week: the title and the
  // trail already say it.
  String? get _status => switch (widget.streak.state) {
        StreakState.active => null,
        StreakState.open => 'Diese Woche ist noch offen.',
        StreakState.paused =>
          'Pausiert. Eine Aktion diese Woche, und deine Flamme brennt wieder.',
        StreakState.none => 'Mit einer Aktion zündest du deine Flamme an.',
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MiSpace.base,
            56,
            MiSpace.base,
            MiSpace.base,
          ),
          child: Material(
            color: colors.tableRaised,
            borderRadius: BorderRadius.circular(MiRadius.card),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(MiSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: AnimatedBuilder(
                            animation: _idle,
                            builder: (context, _) => CustomPaint(
                              painter: FlamePainter(
                                level: widget.streak.flame,
                                phase: _idle.value,
                                colors: colors,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: MiSpace.base),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // The card's step-down size: a status, not a
                              // screen heading.
                              Text(
                                _title,
                                style: text.titleLarge?.copyWith(fontSize: 18),
                              ),
                              if (_status case final status?) ...[
                                const SizedBox(height: MiSpace.xs),
                                Text(
                                  status,
                                  style: text.bodyMedium?.copyWith(
                                    color: colors.onTableMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MiSpace.base),
                    WeekTrail(recent: widget.streak.recent),
                    const SizedBox(height: MiSpace.base),
                    Text(
                      'Du kannst eine Woche pausieren, ohne dass deine Flamme '
                      'erlischt.',
                      style: text.bodyMedium?.copyWith(
                        color: colors.onTableMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The last weeks as a row of cells, this week last: filled where the user
/// did something, so a pause shows as a gap the streak runs across.
class WeekTrail extends StatelessWidget {
  const WeekTrail({required this.recent, super.key});

  final List<bool> recent;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final active = recent.where((w) => w).length;
    return Semantics(
      label: 'In $active der letzten ${recent.length} Wochen dabei',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < recent.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: recent[i] ? colors.topics[2] : null,
                    borderRadius: BorderRadius.circular(4),
                    border: recent[i]
                        ? null
                        : Border.all(
                            color: i == recent.length - 1
                                ? colors.onTableMuted
                                : colors.keyline,
                            width: i == recent.length - 1 ? 1.5 : 1,
                          ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// By [level], a flame of three layers (coral, amber, card stock) or, unlit,
/// its shape in grey (paused: with a wisp of smoke). [phase] (0 to 1,
/// looping) moves the flicker and the smoke; [grow] scales the flame up
/// over the grey shape; [spark] (0 to 1) flies a spark in from the left
/// onto its foot.
class FlamePainter extends CustomPainter {
  FlamePainter({
    required this.level,
    required this.colors,
    this.phase = 0,
    this.grow = 1,
    this.spark,
  });

  final FlameLevel level;
  final MiColors colors;
  final double phase;
  final double grow;
  final double? spark;

  static const _strength = {
    FlameLevel.strong: 1.0,
    FlameLevel.medium: 0.78,
    FlameLevel.ember: 0.56,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final base = Offset(size.width / 2, s * 0.92);
    final full = s * 0.8;
    final strength = (_strength[level] ?? 0) * grow;

    // Unlit, or not yet grown back: the flame's shape in grey.
    if (grow < 1 || _strength[level] == null) {
      final grey = colors.onTableMuted;
      _tongue(canvas, base, full, full * 0.66, 0, grey.withValues(alpha: 0.4));
      _tongue(
        canvas,
        base,
        full * 0.68,
        full * 0.44,
        0,
        grey.withValues(alpha: 0.55),
      );
      _tongue(
        canvas,
        base,
        full * 0.34,
        full * 0.22,
        0,
        colors.table.withValues(alpha: 0.7),
      );
    }

    if (strength > 0) {
      // A soft glow under the fire.
      canvas.drawOval(
        Rect.fromCenter(
          center: base,
          width: s * 0.5,
          height: s * 0.12,
        ),
        Paint()
          ..color = colors.topics[2].withValues(alpha: 0.35 * grow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05),
      );
      final wave = sin(2 * pi * phase);
      final sway = wave * s * 0.04;
      final stretch = 1 + 0.06 * sin(4 * pi * phase + 1);
      final height = full * strength * stretch;
      final flame = base;
      _tongue(canvas, flame, height, height * 0.66, sway, colors.topics[0]);
      _tongue(
        canvas,
        flame,
        height * 0.68,
        height * 0.44,
        sway * 0.7,
        colors.topics[2],
      );
      _tongue(
        canvas,
        flame,
        height * 0.34,
        height * 0.22,
        sway * 0.4,
        colors.cardStock,
      );
    }

    if (level == FlameLevel.smoke && spark == null) {
      _smoke(canvas, s, base.translate(0, -full * 0.85));
    }

    if (spark case final t?) _spark(canvas, s, base, t);
  }

  void _tongue(
    Canvas canvas,
    Offset base,
    double height,
    double width,
    double sway,
    Color color,
  ) {
    final tip = base.translate(sway, -height);
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..cubicTo(
        base.dx - width * 0.8,
        base.dy,
        base.dx - width * 0.5,
        base.dy - height * 0.55,
        tip.dx,
        tip.dy,
      )
      ..cubicTo(
        base.dx + width * 0.5,
        base.dy - height * 0.55,
        base.dx + width * 0.8,
        base.dy,
        base.dx,
        base.dy,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // Two small puffs off the grey tip, half a round apart, rising, drifting
  // and fading.
  void _smoke(Canvas canvas, double s, Offset tip) {
    for (final offset in [0.0, 0.5]) {
      final t = (phase + offset) % 1;
      final center = tip.translate(
        sin(t * 2 * pi) * s * 0.06,
        -t * s * 0.3,
      );
      canvas.drawCircle(
        center,
        s * (0.04 + t * 0.06),
        Paint()
          ..color = colors.onTableMuted.withValues(alpha: 0.6 * (1 - t))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02),
      );
    }
  }

  // An arc from the left onto the wood, with a short fading trail.
  void _spark(Canvas canvas, double s, Offset base, double t) {
    Offset at(double u) {
      final start = base.translate(-s * 1.4, -s * 0.3);
      final control = base.translate(-s * 0.7, -s * 1.1);
      final a = Offset.lerp(start, control, u)!;
      final b = Offset.lerp(control, base, u)!;
      return Offset.lerp(a, b, u)!;
    }

    final eased = Curves.easeIn.transform(t);
    for (var i = 4; i >= 0; i--) {
      final u = (eased - i * 0.05).clamp(0.0, 1.0);
      canvas.drawCircle(
        at(u),
        s * (0.05 - i * 0.008),
        Paint()..color = colors.topics[2].withValues(alpha: 1 - i * 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(FlamePainter old) =>
      old.level != level ||
      old.phase != phase ||
      old.grow != grow ||
      old.spark != spark ||
      old.colors != colors;
}
