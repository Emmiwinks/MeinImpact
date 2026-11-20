import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../../onboarding/rucksack/hanging_tag.dart';
import '../../../onboarding/rucksack/rucksack_bag.dart';
import '../../../tracking/domain/progress.dart';
import '../../../tracking/progress_widgets.dart';
import '../../domain/interest_config.dart';
import '../../domain/interest_weights.dart';
import '../../domain/lebenslagen_catalog.g.dart';
import '../../domain/user_profile.dart';
import 'lebenslagen_picker.dart';
import 'werte_bild.dart';

/// The Profil tab on the card table, in the onboarding's own objects: the
/// values picture as a card that turns over to its scales, the Rucksack with
/// what belongs to the user, and the topics the cards taught. Sections lie
/// on the table divided by keylines.
class ProfileColumn extends StatelessWidget {
  const ProfileColumn({
    required this.profile,
    required this.onEdit,
    required this.onLebenslagenChanged,
    required this.onInterestsChanged,
    this.onEditLebenslagen,
    this.progress,
    super.key,
  });

  final UserProfile? profile;

  /// For the badges; none without it.
  final Progress? progress;
  final VoidCallback onEdit;

  /// Opens the Rucksack instead of the sheet to edit the Lebenslagen.
  final VoidCallback? onEditLebenslagen;
  final ValueChanged<Set<String>> onLebenslagenChanged;
  final ValueChanged<InterestWeights> onInterestsChanged;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          first: true,
          child: _WertebildSection(profile: p, onEdit: onEdit),
        ),
        if (p != null) ...[
          _Section(
            child: _RucksackSection(
              profile: p,
              onChanged: onLebenslagenChanged,
              onOpen: onEditLebenslagen,
            ),
          ),
          if (progress case final progress?)
            // The medals scroll to the screen's edges.
            _Section(flush: true, child: ProfileBadges(progress: progress)),
          _Section(
            child: _TopicsSection(
              interests: p.interests,
              onChanged: onInterestsChanged,
            ),
          ),
        ],
      ],
    );
  }
}

/// One block on the table, below a keyline like the rows in "Alle
/// Aktionen" and Wirkung.
class _Section extends StatelessWidget {
  const _Section({
    required this.child,
    this.first = false,
    this.flush = false,
  });

  final Widget child;
  final bool first;
  // No side margins: the child keeps its own.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final side = flush ? 0.0 : MiSpace.lg;
    return Container(
      padding: EdgeInsets.fromLTRB(
        side,
        first ? 0 : MiSpace.lg,
        side,
        MiSpace.lg,
      ),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: context.mi.keyline)),
            ),
      child: child,
    );
  }
}

/// A heading with an optional text button at its end.
class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

/// An outlined pill on the table for a secondary step ("Fragebogen
/// ausfüllen").
class _OutlinedPill extends StatelessWidget {
  const _OutlinedPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.onTable,
        side: BorderSide(color: colors.onTableMuted),
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: MiFonts.text,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Text(label),
    );
  }
}

/// Opens [child] in a sheet on the card table. Routes do not inherit the
/// tab's theme, so it is handed on.
Future<void> _showTableSheet(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  final colors = context.mi;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.table,
    builder: (_) => Theme(
      data: theme,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            MiSpace.lg,
            0,
            MiSpace.lg,
            MiSpace.xl,
          ),
          child: child,
        ),
      ),
    ),
  );
}

// ── Dein Wertebild ──────────────────────────────────────────────────────

/// One value axis with its two poles, worded like the answers in the
/// questionnaire: -2 is the left answer, +2 the right one.
class _Axis {
  const _Axis(this.name, this.left, this.right);

  final String name;
  final String left;
  final String right;

  String reading(double value) {
    final v = value.clamp(-2.0, 2.0);
    if (v.abs() < 0.5) return 'ausgeglichen';
    final pole = v < 0 ? left : right;
    return v.abs() < 1.25 ? 'eher $pole' : 'klar $pole';
  }
}

const _axes = [
  _Axis('Wirtschaft', 'Umverteilung', 'Freier Markt'),
  _Axis('Diplomatie', 'National', 'International'),
  _Axis('Freiheit', 'Bürgerrechte', 'Sicherheit'),
  _Axis('Wandel', 'Bewahren', 'Verändern'),
];

/// The picture as a card that can be shown to anyone: its front is only
/// the picture, and only turning it over shows where the user stands.
class _WertebildSection extends StatelessWidget {
  const _WertebildSection({required this.profile, required this.onEdit});

  final UserProfile? profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final p = profile;
    final answers = [for (final k in werteQuestionKeys) p?.werte[k]];
    if (p == null || answers.every((a) => a == null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Heading('Dein Wertebild'),
          const SizedBox(height: MiSpace.sm),
          Text(
            'Noch nicht ausgefüllt.',
            style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
          ),
          const SizedBox(height: MiSpace.base),
          _OutlinedPill(label: 'Fragebogen ausfüllen', onPressed: onEdit),
        ],
      );
    }
    return _WertebildCard(
      answers: answers,
      values: [
        p.axisEqualityMarkets,
        p.axisNationGlobe,
        p.axisLibertyAuthority,
        p.axisTraditionProgress,
      ],
      onEdit: onEdit,
    );
  }
}

class _WertebildCard extends StatefulWidget {
  const _WertebildCard({
    required this.answers,
    required this.values,
    required this.onEdit,
  });

  final List<double?> answers;
  // One per axis, -2.0 to +2.0.
  final List<double> values;
  final VoidCallback onEdit;

  @override
  State<_WertebildCard> createState() => _WertebildCardState();
}

class _WertebildCardState extends State<_WertebildCard>
    with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  bool _shown = false;

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _shown = !_shown);
    if (MiMotion.reduced(context)) {
      _turn.value = _shown ? 1 : 0;
    } else if (_shown) {
      _turn.forward();
    } else {
      _turn.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          'Dein Wertebild',
          action: 'Neu malen',
          onAction: widget.onEdit,
        ),
        const SizedBox(height: MiSpace.base),
        Center(
          child: Semantics(
            button: true,
            label: _shown
                ? 'Deine Werte. Tippen, um sie zu verbergen.'
                : 'Dein Wertebild. Tippen, um deine Werte anzuzeigen.',
            child: GestureDetector(
              key: const ValueKey('wertebild'),
              onTap: _toggle,
              child: SizedBox.square(
                dimension: 250,
                child: AnimatedBuilder(
                  animation: _turn,
                  builder: (context, _) {
                    final angle =
                        MiMotion.ease.transform(_turn.value) * math.pi;
                    final back = angle > math.pi / 2;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(angle),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..rotateY(back ? math.pi : 0),
                        child: _Face(
                          padding: back
                              ? const EdgeInsets.fromLTRB(18, 22, 18, 18)
                              : const EdgeInsets.all(10),
                          child: back
                              ? _Scales(values: widget.values)
                              : WerteBild(answers: widget.answers),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: MiSpace.base + 4),
        Text(
          _shown ? 'Zum Verbergen tippen' : 'Zum Anzeigen tippen',
          style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// One face of the picture card: card stock with the card shadow.
class _Face extends StatelessWidget {
  const _Face({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.cardStock,
        borderRadius: BorderRadius.circular(MiRadius.card),
        border: Border.all(color: colors.keyline),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The back of the picture card: each axis as a compact scale, marked with
/// its shape from the picture instead of its name.
class _Scales extends StatelessWidget {
  const _Scales({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final poles = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 11.5,
          color: colors.onCardMuted,
        );
    // Large text shrinks the scales to fit the card rather than cutting
    // them off.
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: constraints.maxWidth,
          child: _column(colors, poles),
        ),
      ),
    );
  }

  Widget _column(MiColors colors, TextStyle? poles) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 13,
      children: [
        for (var i = 0; i < _axes.length; i++)
          Semantics(
            label: '${_axes[i].name}: ${_axes[i].reading(values[i])}, '
                'zwischen ${_axes[i].left} und ${_axes[i].right}',
            excludeSemantics: true,
            child: Row(
              children: [
                CustomPaint(
                  size: const Size.square(22),
                  painter: _GlyphPainter(i, colors.topics[i]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 16,
                        child: CustomPaint(
                          painter: _ScalePainter(
                            value: values[i].clamp(-2.0, 2.0) / 2,
                            color: colors.topics[i],
                            ink: colors.onCard,
                            muted: colors.onCardMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _axes[i].left,
                              style: poles,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(_axes[i].right, style: poles, maxLines: 1),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The axis's shape in the picture: circle, half disc, bar, triangle.
class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.axis, this.color);

  final int axis;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 22);
    final paint = Paint()..color = color;
    switch (axis) {
      case 0:
        canvas.drawCircle(const Offset(11, 11), 9, paint);
      case 1:
        canvas.drawPath(
          Path()
            ..moveTo(2, 15)
            ..arcToPoint(const Offset(20, 15), radius: const Radius.circular(9))
            ..close(),
          paint,
        );
      case 2:
        canvas.drawRRect(
          RRect.fromLTRBR(1, 7.5, 21, 14.5, const Radius.circular(3.5)),
          paint,
        );
      default:
        canvas.drawPath(
          Path()
            ..moveTo(11, 2)
            ..lineTo(20.5, 19)
            ..lineTo(1.5, 19)
            ..close(),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.axis != axis || old.color != color;
}

/// A thin track with a centre tick; a bar in the axis colour runs from the
/// centre to a dot where the user stands. [value] is -1..1.
class _ScalePainter extends CustomPainter {
  _ScalePainter({
    required this.value,
    required this.color,
    required this.ink,
    required this.muted,
  });

  final double value;
  final Color color;
  final Color ink;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final y = size.height / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(0, y - 2, size.width, y + 2, const Radius.circular(2)),
      Paint()..color = ink.withValues(alpha: 0.12),
    );
    // The dot stays inside the track at the ends.
    final x = mid + value * (mid - 8);
    canvas
      ..drawRRect(
        RRect.fromLTRBR(
          math.min(mid, x),
          y - 3,
          math.max(mid, x),
          y + 3,
          const Radius.circular(3),
        ),
        Paint()..color = color,
      )
      ..drawLine(
        Offset(mid, y - 6),
        Offset(mid, y + 6),
        Paint()
          ..color = muted.withValues(alpha: 0.6)
          ..strokeWidth = 2,
      )
      ..drawCircle(Offset(x, y), 6.5, Paint()..color = color)
      ..drawCircle(
        Offset(x, y),
        6.5,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
  }

  @override
  bool shouldRepaint(_ScalePainter old) =>
      old.value != value ||
      old.color != color ||
      old.ink != ink ||
      old.muted != muted;
}

// ── Was zu dir gehört ───────────────────────────────────────────────────

/// The Rucksack from the onboarding, small: the picture, the packed tags
/// and the PLZ on its luggage tag, with the Wahlkreis beside it. Below, the
/// public Lebenslagen as tags in their area colours; private ones only show
/// as tag tops in the Privatfach. "Umpacken" opens the Rucksack again.
class _RucksackSection extends StatelessWidget {
  const _RucksackSection({
    required this.profile,
    required this.onChanged,
    this.onOpen,
  });

  final UserProfile profile;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback? onOpen;

  // The luggage tag hangs this far left of the bag.
  static const _luggage = 56.0;
  static const _bagWidth = 128.0;

  void _edit(BuildContext context) {
    final open = onOpen;
    if (open != null) return open();
    var current = profile.lebenslagen;
    _showTableSheet(
      context,
      StatefulBuilder(
        builder: (context, setSheetState) => LebenslagenPicker(
          selected: current,
          onChanged: (ids) {
            setSheetState(() => current = ids);
            onChanged(ids);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: colors.onTableMuted);
    final answers = [for (final k in werteQuestionKeys) profile.werte[k]];
    // Grouped by area in the catalog's order, so the colours run together;
    // the area names stay off.
    final shown = [
      for (final area in kLebenslageAreas)
        for (final item in kLebenslagen)
          if (item.area == area &&
              !item.isPrivate &&
              profile.lebenslagen.contains(item.id))
            item,
    ];
    final wahlkreis = profile.mdbWahlkreis;
    final mdb = profile.mdbName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          'Was zu dir gehört',
          action: 'Umpacken',
          onAction: () => _edit(context),
        ),
        const SizedBox(height: MiSpace.base),
        Row(
          children: [
            const SizedBox(width: _luggage),
            RucksackBag(
              width: _bagWidth,
              items: packedLebenslagen(profile.lebenslagen, colors.topics),
              answers: answers.every((a) => a == null) ? null : answers,
              plz: profile.plz,
              place: wahlkreis,
            ),
            const SizedBox(width: MiSpace.base + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (profile.plz == null)
                    Text('Keine PLZ angegeben.', style: muted)
                  else ...[
                    Text(
                      wahlkreis ?? profile.plz!,
                      style: text.titleMedium?.copyWith(
                        fontFamily: MiFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (mdb != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        profile.mdbParty == null
                            ? 'Im Bundestag: $mdb'
                            : 'Im Bundestag: $mdb, ${profile.mdbParty}',
                        style: muted,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: MiSpace.base + 2),
        if (shown.isEmpty)
          Text(
            profile.lebenslagen.isEmpty
                ? 'Noch nichts ausgewählt.'
                : 'Deine Auswahl liegt im Privatfach.',
            style: muted,
          )
        else
          Wrap(
            spacing: MiSpace.sm,
            runSpacing: MiSpace.md - 2,
            children: [
              for (var i = 0; i < shown.length; i++)
                _MiniTag(
                  label: shown[i].label,
                  color: lebenslageColor(shown[i], colors.topics),
                  // A little askew, each its own way, like on the area cards.
                  tilt: (((i * 7) % 5) - 2) * 0.7,
                ),
            ],
          ),
      ],
    );
  }
}

/// A packed Lebenslage as a small tag: notched end, eyelet, soft shadow. Card
/// stock with the area's colour only in the eyelet, so the profile keeps its
/// loud colour for the picture and the stickers.
class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color, this.tilt = 0});

  final String label;
  final Color color;

  /// Degrees.
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Transform.rotate(
      angle: tilt * math.pi / 180,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 7, 11, 7),
            decoration: ShapeDecoration(
              color: colors.cardStock,
              shape: TagBorder(
                notch: 9,
                radius: 7,
                side: BorderSide(color: colors.keyline),
              ),
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: MiFonts.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: colors.onCard,
              ),
            ),
          ),
          Positioned(
            left: 7,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: colors.onCard, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Deine Themen ────────────────────────────────────────────────────────

/// A mirror of what the cards taught: the topics the feed shows more often,
/// strongest first. Steering happens on the cards ("öfter" / "seltener");
/// here a topic can only be forgotten.
class _TopicsSection extends StatelessWidget {
  const _TopicsSection({required this.interests, required this.onChanged});

  final InterestWeights interests;
  final ValueChanged<InterestWeights> onChanged;

  static const _config = InterestConfig();

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final favourites = interests.favourites(DateTime.now(), _config);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Deine Themen'),
        const SizedBox(height: MiSpace.sm),
        if (favourites.isEmpty)
          Text(
            'Was du auf den Karten öffnest, erledigst oder auf „öfter“ '
            'stellst, zeigen wir dir häufiger. Diese Themen stehen dann hier.',
            style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
          )
        else
          Wrap(
            spacing: MiSpace.sm,
            runSpacing: MiSpace.sm,
            children: [
              for (final tag in favourites)
                _ForgettableChip(
                  key: ValueKey('topic-$tag'),
                  label: tag,
                  onForget: () =>
                      onChanged(interests.forget(tag, DateTime.now(), _config)),
                ),
            ],
          ),
      ],
    );
  }
}

/// A topic pill with an × that sets it back to neutral.
class _ForgettableChip extends StatelessWidget {
  const _ForgettableChip({
    required this.label,
    required this.onForget,
    super.key,
  });

  final String label;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return InputChip(
      label: Text(label),
      onDeleted: onForget,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      deleteButtonTooltipMessage: '$label vergessen',
      deleteIconColor: colors.onTableMuted,
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: colors.onTableMuted)),
      labelStyle: TextStyle(
        fontFamily: MiFonts.text,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: colors.onTable,
      ),
    );
  }
}
