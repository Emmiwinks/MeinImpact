import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/mi_theme.dart';
import '../feed/domain/opportunity.dart';
import '../feed/presentation/hand/topic_art.dart';
import 'domain/progress.dart';

/// A badge as a sticker (art from tool/badges/build.mjs): a little askew,
/// each its own way, with a soft shadow, as if stuck into an album. A topic
/// sticker carries its tier as a seal, bronze, silver or gold. Not earned
/// yet, it is a faded grey ghost without shadow or seal.
class BadgeSticker extends StatelessWidget {
  const BadgeSticker({
    required this.asset,
    this.size = 56,
    this.earned = true,
    this.tier,
    this.tilt,
    super.key,
  });

  final String asset;
  final double size;
  final bool earned;

  /// Shows the seal; null on the track over all topics.
  final int? tier;

  /// Radians; by default the sticker's own, from its file name.
  final double? tilt;

  static const _greyscale = ColorFilter.matrix([
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0, //
    0.33, 0.33, 0.33, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  // Between -7 and 7 degrees, always the same for the same sticker.
  static double _ownTilt(String asset) {
    final sum = asset.codeUnits.fold<int>(0, (a, b) => a * 31 + b & 0xFFFF);
    return ((sum % 15) - 7) * pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final picture = SvgPicture.asset(asset, width: size, height: size);
    if (!earned) {
      return ExcludeSemantics(
        child: Opacity(
          opacity: 0.3,
          child: ColorFiltered(colorFilter: _greyscale, child: picture),
        ),
      );
    }
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: tilt ?? _ownTilt(asset),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: Offset(0, size * 0.04),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: size * 0.03,
                    sigmaY: size * 0.03,
                  ),
                  child: SvgPicture.asset(
                    asset,
                    width: size,
                    height: size,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.35),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
              picture,
              if (tier case final tier?)
                Positioned(
                  right: size * 0.02,
                  bottom: size * 0.02,
                  child: CustomPaint(
                    size: Size.square(size * 0.24),
                    painter: _SealPainter(tier),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tier seal: bronze, silver or gold with an ink star.
class _SealPainter extends CustomPainter {
  _SealPainter(this.tier);

  final int tier;

  static const _metal = {
    1: Color(0xFFD9935B),
    2: Color(0xFFC9CED6),
    3: Color(0xFFFFBF3C),
  };
  static const _ink = Color(0xFF101820);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas
      ..drawCircle(c, r + r * 0.18, Paint()..color = const Color(0xFFFFFCF8))
      ..drawCircle(c, r, Paint()..color = _metal[tier] ?? _metal[1]!)
      ..drawCircle(
        c,
        r,
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.22,
      );
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -pi / 2 + i * pi / 5;
      final radius = i.isEven ? r * 0.58 : r * 0.25;
      final point = c + Offset(cos(angle), sin(angle)) * radius;
      i == 0
          ? star.moveTo(point.dx, point.dy)
          : star.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(star..close(), Paint()..color = _ink);
  }

  @override
  bool shouldRepaint(_SealPainter old) => old.tier != tier;
}

// Room for two lines of label under a medal as the user's text size grows.
double _textGrowth(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5).toDouble();

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final TopicBadge badge;

  @override
  Widget build(BuildContext context) {
    final next = badge.nextAt;
    final progress = next == null ? 'Alle erreicht' : '${badge.actions}/$next';
    return _Tile(
      medal: BadgeSticker(
        asset: badge.asset,
        size: 64,
        earned: badge.tier > 0,
        tier: badge.tier > 0 ? badge.tier : null,
      ),
      name: badge.name ?? badge.topic,
      muted: badge.name == null,
      detail: progress,
      semantics: badge.name == null
          ? '${badge.topic}: noch kein Abzeichen, $progress'
          : '${badge.name}, ${badge.earnedFor}, $progress',
    );
  }
}

/// A medal with its name and how far the next one is.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.medal,
    required this.name,
    required this.detail,
    required this.semantics,
    this.muted = false,
  });

  final Widget medal;
  final String name;
  final String detail;
  final String semantics;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: semantics,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 92,
          child: Column(
            children: [
              medal,
              const SizedBox(height: MiSpace.xs),
              // One line: long single words shrink instead of breaking.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  name,
                  maxLines: 1,
                  style: text.labelMedium?.copyWith(
                    color: muted ? colors.onTableMuted : null,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  detail,
                  maxLines: 1,
                  style: text.labelMedium?.copyWith(
                    color: colors.onTableMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The album with every sticker, earned or not; opened from the profile.
Future<void> showBadgeAlbum(BuildContext context, Progress progress) {
  final theme = Theme.of(context);
  Widget heading(BuildContext context, String title, String detail) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          MiSpace.lg,
          MiSpace.base,
          MiSpace.lg,
          MiSpace.base,
        ),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: MiSpace.xs),
              Text(
                detail,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: context.mi.onTableMuted),
              ),
            ],
          ),
        ),
      );
  Widget grid(BuildContext context, List<Widget> tiles) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: MiSpace.base),
        sliver: SliverGrid.count(
          crossAxisCount: 3,
          childAspectRatio: 1 / (1.1 * _textGrowth(context)),
          mainAxisSpacing: MiSpace.sm,
          children: [for (final t in tiles) Center(child: t)],
        ),
      );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Theme(
      data: theme,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, controller) => CustomScrollView(
          controller: controller,
          slivers: [
            heading(context, 'Alle Themen', 'Für alle Aktionen zusammen.'),
            grid(context, [
              for (final m in kMilestones)
                _Tile(
                  medal: BadgeSticker(
                    asset: m.asset,
                    size: 64,
                    earned: progress.actions >= m.count,
                  ),
                  name: m.title,
                  muted: progress.actions < m.count,
                  detail: m.count == 1 ? '1 Aktion' : '${m.count} Aktionen',
                  semantics: '${m.title}, ${m.count} Aktionen, '
                      '${progress.actions >= m.count ? 'erreicht' : 'noch nicht erreicht'}',
                ),
            ]),
            heading(
              context,
              'Pro Thema',
              'Bei ${kBadgeTiers[0]}, ${kBadgeTiers[1]} und '
                  '${kBadgeTiers[2]} Aktionen zu einem Thema.',
            ),
            grid(context, [
              for (final badge in progress.badges) _BadgeTile(badge: badge),
            ]),
            const SliverToBoxAdapter(child: SizedBox(height: MiSpace.xl)),
          ],
        ),
      ),
    ),
  );
}

/// The moment after "Fertig" when the action earned badges: one face-down
/// card per badge, dealt onto the table; each tap turns one over.
Future<void> showProgressMoment(BuildContext context, ProgressMoment moment) {
  final reduced = MiMotion.reduced(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Neue Abzeichen',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: reduced ? Duration.zero : MiMotion.settle,
    pageBuilder: (_, __, ___) => _RevealScreen(moment: moment),
    transitionBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _Prize {
  const _Prize({
    required this.label,
    required this.title,
    required this.medal,
    required this.burst,
  });

  final String label;
  final String title;
  final Widget Function(double size) medal;
  // The colours the turned card bursts in.
  final List<Color> burst;
}

class _RevealScreen extends StatefulWidget {
  const _RevealScreen({required this.moment});

  final ProgressMoment moment;

  @override
  State<_RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends State<_RevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _deal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  final _turned = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MiMotion.reduced(context)) {
        _deal.value = 1;
      } else {
        _deal.forward();
      }
    });
  }

  @override
  void dispose() {
    _deal.dispose();
    super.dispose();
  }

  List<_Prize> _prizes(MiColors colors) => [
        if (widget.moment.milestone case final m?)
          _Prize(
            label: '${m.count}. Aktion',
            title: m.title,
            medal: (size) => BadgeSticker(asset: m.asset, size: size),
            burst: colors.topics,
          ),
        for (final badge in widget.moment.badges)
          _Prize(
            label: badge.earnedFor,
            title: badge.name!,
            medal: (size) =>
                BadgeSticker(asset: badge.asset, size: size, tier: badge.tier),
            burst: [
              TopicLook.forTags([badge.tag], OpportunityKind.other)
                  .face(colors),
              colors.topics[2],
              colors.cardStock,
            ],
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final prizes = _prizes(colors);
    final done = _turned.length == prizes.length;
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = min(
      prizes.length == 1 ? 200.0 : 150.0,
      (width - 2 * MiSpace.lg - (prizes.length - 1) * MiSpace.md) /
          prizes.length,
    );
    final light = TextStyle(color: colors.cardStock);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(MiSpace.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                prizes.length == 1 ? 'Neues Abzeichen' : 'Neue Abzeichen',
                textAlign: TextAlign.center,
                style: text.headlineMedium?.merge(light),
              ),
              const SizedBox(height: MiSpace.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < prizes.length; i++) ...[
                    if (i > 0) const SizedBox(width: MiSpace.md),
                    _DealtCard(
                      deal: _deal,
                      index: i,
                      count: prizes.length,
                      width: cardWidth,
                      prize: prizes[i],
                      turned: _turned.contains(i),
                      onTurn: () => setState(() => _turned.add(i)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: MiSpace.xl),
              SizedBox(
                height: 52,
                child: AnimatedSwitcher(
                  duration: MiMotion.reduced(context)
                      ? Duration.zero
                      : MiMotion.settle,
                  child: done
                      ? FilledButton(
                          key: const ValueKey('weiter'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.cardStock,
                            foregroundColor: colors.onCard,
                            minimumSize: const Size(200, 52),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Weiter'),
                        )
                      : Center(
                          key: const ValueKey('hint'),
                          child: Text(
                            'Tippen zum Aufdecken',
                            style: text.bodyLarge?.merge(light),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One prize card: dealt in from below, face down until tapped, then it
/// turns over with a jump and bursts.
class _DealtCard extends StatefulWidget {
  const _DealtCard({
    required this.deal,
    required this.index,
    required this.count,
    required this.width,
    required this.prize,
    required this.turned,
    required this.onTurn,
  });

  final Animation<double> deal;
  final int index;
  final int count;
  final double width;
  final _Prize prize;
  final bool turned;
  final VoidCallback onTurn;

  @override
  State<_DealtCard> createState() => _DealtCardState();
}

class _DealtCardState extends State<_DealtCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _tap() {
    if (widget.turned) return;
    widget.onTurn();
    if (MiMotion.reduced(context)) {
      _turn.value = 1;
    } else {
      _turn.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 1.4;
    // Each card's own slice of the deal, one after the other.
    final start = widget.index * 0.18;
    final dealt = CurvedAnimation(
      parent: widget.deal,
      curve: Interval(start, min(1, start + 0.6), curve: Curves.easeOutBack),
    );
    // Fanned a little, like cards just put down.
    final rest = widget.count == 1
        ? 0.0
        : (widget.index - (widget.count - 1) / 2) * 0.06;
    return Semantics(
      button: !widget.turned,
      label: widget.turned
          ? '${widget.prize.title}, ${widget.prize.label}'
          : 'Verdeckte Karte, zum Aufdecken tippen',
      child: GestureDetector(
        onTap: _tap,
        child: AnimatedBuilder(
          animation: Listenable.merge([dealt, _turn]),
          builder: (context, _) {
            final d = dealt.value;
            final t = _turn.value;
            // The turn: up to the middle, over, and a jump at the end.
            final flip = Curves.easeInOutCubic.transform(min(1, t / 0.4));
            final jump = t < 0.4
                ? 1 + 0.12 * flip
                : 1.12 - 0.12 * Curves.elasticOut.transform((t - 0.4) / 0.6);
            final angle = flip * pi;
            final showFront = angle > pi / 2;
            return SizedBox(
              width: widget.width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (t > 0.35)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _BurstPainter(
                            progress: ((t - 0.35) / 0.65).clamp(0, 1),
                            colors: widget.prize.burst,
                            seed: widget.index,
                          ),
                        ),
                      ),
                    ),
                  Opacity(
                    opacity: d.clamp(0, 1),
                    child: Transform.translate(
                      offset: Offset(0, (1 - d) * 220),
                      child: Transform.rotate(
                        angle:
                            rest + (1 - d) * (widget.index.isEven ? -0.5 : 0.5),
                        child: Transform.scale(
                          scale: jump,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0012)
                              ..rotateY(angle),
                            child: showFront
                                ? Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()..rotateY(pi),
                                    child: _PrizeFace(
                                      prize: widget.prize,
                                      width: widget.width,
                                    ),
                                  )
                                : const _PrizeBack(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PrizeBack extends StatelessWidget {
  const _PrizeBack();

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Container(
      decoration: BoxDecoration(
        color: colors.onCard,
        borderRadius: BorderRadius.circular(MiRadius.tile + 4),
        border: Border.all(color: colors.cardStock, width: 5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _SparklePainter(
          star: colors.topics[2],
          dots: colors.cardStock.withValues(alpha: 0.18),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PrizeFace extends StatelessWidget {
  const _PrizeFace({required this.prize, required this.width});

  final _Prize prize;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    // The medals read their pips and frames off the table colours; on the
    // card they are ink on stock.
    final onCard = Theme.of(context).copyWith(
      extensions: [
        colors.copyWith(
          onTable: colors.onCard,
          onTableMuted: colors.onCardMuted,
          keyline: colors.onCard.withValues(alpha: 0.15),
        ),
      ],
    );
    return Theme(
      data: onCard,
      child: Container(
        padding: EdgeInsets.all(width * 0.08),
        decoration: BoxDecoration(
          color: colors.cardStock,
          borderRadius: BorderRadius.circular(MiRadius.tile + 4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            prize.medal(width * 0.7),
            SizedBox(height: width * 0.04),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                prize.title,
                maxLines: 1,
                style: text.titleLarge?.copyWith(
                  color: colors.onCard,
                  fontSize: min(21, width * 0.14),
                ),
              ),
            ),
            SizedBox(height: width * 0.03),
            Text(
              prize.label,
              textAlign: TextAlign.center,
              maxLines: 3,
              style: text.labelMedium?.copyWith(
                color: colors.onCardMuted,
                fontSize: min(13, width * 0.09),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A four-pointed star on a field of dots: the back of a prize card.
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.star, required this.dots});

  final Color star;
  final Color dots;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = dots;
    final step = size.width / 7;
    for (var x = step / 2; x < size.width; x += step) {
      for (var y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), step * 0.08, dot);
      }
    }
    final c = size.center(Offset.zero);
    final r = size.width * 0.24;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = star);
  }

  @override
  bool shouldRepaint(_SparklePainter old) =>
      old.star != star || old.dots != dots;
}

/// Flat shapes flying out of a turned card and fading: the same circles,
/// squares and triangles the topic art is made of.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.progress,
    required this.colors,
    required this.seed,
  });

  final double progress;
  final List<Color> colors;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final random = Random(seed * 31 + 7);
    final center = size.center(Offset.zero);
    final out = Curves.easeOutCubic.transform(progress);
    final fade = 1 - Curves.easeIn.transform(progress);
    for (var i = 0; i < 16; i++) {
      final angle = i / 16 * 2 * pi + random.nextDouble() * 0.4;
      final reach = size.width * (0.6 + random.nextDouble() * 0.6);
      final position = center + Offset(cos(angle), sin(angle)) * reach * out;
      final s = size.width * (0.04 + random.nextDouble() * 0.04);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: fade);
      canvas
        ..save()
        ..translate(position.dx, position.dy)
        ..rotate(angle + progress * 4);
      switch (i % 3) {
        case 0:
          canvas.drawCircle(Offset.zero, s, paint);
        case 1:
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: s * 2, height: s * 2),
            paint,
          );
        default:
          canvas.drawPath(
            Path()
              ..moveTo(0, -s * 1.2)
              ..lineTo(s * 1.1, s)
              ..lineTo(-s * 1.1, s)
              ..close(),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.seed != seed;
}
