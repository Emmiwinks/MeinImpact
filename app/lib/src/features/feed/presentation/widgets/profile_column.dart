import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../../notifications/notifications.dart';
import '../../../onboarding/rucksack/rucksack_bag.dart';
import '../../../onboarding/stadthaushalt/stadthaushalt.dart';
import '../../../tracking/domain/progress.dart';
import '../../../tracking/progress_widgets.dart';
import '../../domain/interest_config.dart';
import '../../domain/interest_weights.dart';
import '../../domain/opportunity.dart';
import '../../domain/topic_tags.g.dart';
import '../../domain/user_profile.dart';
import '../hand/topic_art.dart';
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
    this.onEditPrioritaeten,
    this.onFillIn,
    this.progress,
    this.onFeedback,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    super.key,
  });

  final UserProfile? profile;

  /// Light, dark or the phone's; no row to choose without the callback.
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  /// Opens the beta feedback sheet; no feedback row without it.
  final VoidCallback? onFeedback;

  /// For the badges; none without it.
  final Progress? progress;
  final VoidCallback onEdit;

  /// Opens the Rucksack instead of the sheet to edit the Lebenslagen.
  final VoidCallback? onEditLebenslagen;

  /// Opens the Stadthaushalt again ("Neu verteilen").
  final VoidCallback? onEditPrioritaeten;

  /// Starts the whole questionnaire, for a profile that put it off.
  final VoidCallback? onFillIn;
  final ValueChanged<Set<String>> onLebenslagenChanged;
  final ValueChanged<InterestWeights> onInterestsChanged;

  static const _config = InterestConfig();

  @override
  Widget build(BuildContext context) {
    final p = profile;
    // Put off: the questionnaire stands in for its three answers.
    final browsing = p != null && p.browsing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The one big thing on the page: the picture (or the way to it).
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MiSpace.lg,
            0,
            MiSpace.lg,
            MiSpace.lg,
          ),
          child: browsing
              ? _FillInSection(onStart: onFillIn)
              : _WertebildSection(profile: p, onEdit: onEdit),
        ),
        if (p != null) ..._rows(context, p),
      ],
    );
  }

  // Everything else as one short row each; a tap opens the full view.
  List<Widget> _rows(BuildContext context, UserProfile p) {
    final colors = context.mi;
    return [
      if (!p.browsing) ...[
        _ProfileRow(
          key: const ValueKey('row-rucksack'),
          title: 'Was zu dir gehört',
          thumb: FittedBox(
            child: RucksackBag(
              width: 54,
              items: packedLebenslagen(p.lebenslagen, colors.topics),
            ),
          ),
          onTap: () => _editLebenslagen(context, p),
        ),
        _ProfileRow(
          key: const ValueKey('row-haushalt'),
          title: 'Dein Stadthaushalt',
          thumb: const TalerHaeufchen(),
          onTap: onEditPrioritaeten,
        ),
      ],
      if (progress case final progress?)
        _ProfileRow(
          key: const ValueKey('row-badges'),
          title: 'Abzeichen',
          thumb: progress.earned.isEmpty
              ? const Icon(Icons.emoji_events_outlined)
              : BadgeSticker(
                  asset: progress.earned.last.asset,
                  size: 44,
                  tier: progress.earned.last.tier,
                ),
          onTap: () => showBadgeAlbum(context, progress),
        ),
      _ProfileRow(
        key: const ValueKey('row-themen'),
        title: 'Deine Themen',
        thumb: _TopicFan(
          tags:
              p.interests.favourites(DateTime.now(), _config).take(3).toList(),
        ),
        onTap: () => _showTopics(context, p),
      ),
      if (Notifications.current.available)
        _ProfileRow(
          key: const ValueKey('row-notifications'),
          title: 'Benachrichtigungen',
          thumb: const Icon(Icons.notifications_none_rounded),
          onTap: Notifications.current.openSettings,
          leavesApp: true,
        ),
      if (onThemeModeChanged case final onChanged?)
        _ProfileRow(
          key: const ValueKey('row-darstellung'),
          title: 'Hell oder dunkel',
          thumb: Icon(_AppearanceChoice.iconFor(themeMode)),
          onTap: () => _showAppearance(context, onChanged),
        ),
      if (onFeedback case final onFeedback?)
        _ProfileRow(
          key: const ValueKey('row-feedback'),
          title: 'Dein Feedback',
          thumb: const Icon(Icons.chat_bubble_outline_rounded),
          onTap: onFeedback,
        ),
    ];
  }

  // The Rucksack screen when there is one, else the picker in a sheet.
  void _editLebenslagen(BuildContext context, UserProfile p) {
    final open = onEditLebenslagen;
    if (open != null) return open();
    var current = p.lebenslagen;
    _showTableSheet(
      context,
      StatefulBuilder(
        builder: (context, setSheetState) => LebenslagenPicker(
          selected: current,
          onChanged: (ids) {
            setSheetState(() => current = ids);
            onLebenslagenChanged(ids);
          },
        ),
      ),
    );
  }

  void _showTopics(BuildContext context, UserProfile p) {
    var current = p.interests;
    _showTableSheet(
      context,
      StatefulBuilder(
        builder: (context, setSheetState) => _TopicsSection(
          interests: current,
          onChanged: (weights) {
            setSheetState(() => current = weights);
            onInterestsChanged(weights);
          },
        ),
      ),
      short: true,
    );
  }

  // The sheet takes the app's theme as it is when opened; a new choice
  // closes it, so the whole app turns at once and nothing is left in the
  // old colours.
  void _showAppearance(
    BuildContext context,
    ValueChanged<ThemeMode> onChanged,
  ) {
    _showTableSheet(
      context,
      Builder(
        builder: (sheetContext) => _AppearanceChoice(
          selected: themeMode,
          onChanged: (mode) {
            Navigator.of(sheetContext).pop();
            onChanged(mode);
          },
        ),
      ),
      short: true,
    );
  }
}

/// Light, dark or like the phone, as three segments.
class _AppearanceChoice extends StatelessWidget {
  const _AppearanceChoice({required this.selected, required this.onChanged});

  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  static IconData iconFor(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  static const _labels = {
    ThemeMode.system: 'Wie Handy',
    ThemeMode.light: 'Hell',
    ThemeMode.dark: 'Dunkel',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Hell oder dunkel'),
        const SizedBox(height: MiSpace.base),
        SegmentedButton<ThemeMode>(
          key: const ValueKey('appearance-choice'),
          showSelectedIcon: false,
          segments: [
            for (final mode in _labels.keys)
              // Words only: with icons "Wie Handy" breaks onto two lines.
              ButtonSegment(value: mode, label: Text(_labels[mode]!)),
          ],
          selected: {selected},
          onSelectionChanged: (modes) => onChanged(modes.single),
          style: SegmentedButton.styleFrom(
            foregroundColor: colors.onTable,
            selectedForegroundColor: colors.onTable,
            selectedBackgroundColor: colors.onTable.withValues(alpha: 0.12),
            side: BorderSide(color: colors.onTableMuted),
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(
              fontFamily: MiFonts.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Themen row's picture: up to three tiny topic cards fanned out like
/// the hand, the strongest topic in front; before any are learnt, the first
/// three topics stand in.
class _TopicFan extends StatelessWidget {
  const _TopicFan({required this.tags});

  // Strongest first.
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final shown = tags.isEmpty ? kTopicTags.take(3).toList() : tags;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Back to front, so the strongest lies on top.
          for (var i = shown.length - 1; i >= 0; i--)
            Transform.translate(
              offset: Offset(_spread(i, shown.length) * 9, 1),
              child: Transform.rotate(
                angle: _spread(i, shown.length) * 0.26,
                alignment: Alignment.bottomCenter,
                child: _MiniCard(tag: shown[i]),
              ),
            ),
        ],
      ),
    );
  }

  // -1, 0, 1 across the fan, the front card in the middle.
  static double _spread(int i, int count) => switch ((count, i)) {
        (1, _) => 0,
        (2, 0) => -0.5,
        (2, _) => 0.5,
        (_, 0) => 0,
        (_, 1) => -1,
        _ => 1,
      };
}

/// One tiny topic card: the topic's art in a rim of card stock.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: context.mi.cardStock,
        borderRadius: BorderRadius.circular(5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: TopicArt(
          look: TopicLook.forTags([tag], OpportunityKind.petition),
        ),
      ),
    );
  }
}

/// One part of the profile: a picture and its name, nothing more (user: no
/// subtitles needed). The whole row opens the full view (or, with [leavesApp], a place
/// outside the app).
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.title,
    required this.thumb,
    required this.onTap,
    this.leavesApp = false,
    super.key,
  });

  final String title;
  final Widget thumb;
  final VoidCallback? onTap;
  final bool leavesApp;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.keyline)),
      ),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MiSpace.lg,
                vertical: MiSpace.md,
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.onTable.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(MiRadius.tile),
                      ),
                      child: IconTheme(
                        data: IconThemeData(color: colors.onTable, size: 26),
                        child: Center(child: thumb),
                      ),
                    ),
                  ),
                  const SizedBox(width: MiSpace.base),
                  Expanded(child: Text(title, style: text.titleMedium)),
                  const SizedBox(width: MiSpace.sm),
                  Icon(
                    leavesApp
                        ? Icons.open_in_new_rounded
                        : Icons.chevron_right_rounded,
                    size: leavesApp ? 20 : 24,
                    color: colors.onTableMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// For someone who put the questionnaire off: why the hand is random, and
/// the way to the whole questionnaire.
class _FillInSection extends StatelessWidget {
  const _FillInSection({required this.onStart});

  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Dein Profil'),
        const SizedBox(height: MiSpace.sm),
        Text(
          'Noch nicht ausgefüllt. Bis dahin bekommst du Aktionen bunt '
          'gemischt, nicht die, die zu dir passen.',
          style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
        ),
        const SizedBox(height: MiSpace.base),
        FilledButton(
          onPressed: onStart,
          style: colors.tableButton,
          child: const Text('Fragebogen ausfüllen · ca. 5 Minuten'),
        ),
      ],
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
/// tab's theme, so it is handed on. A [short] sheet is as tall as its
/// content; otherwise it opens at 90% for long lists.
Future<void> _showTableSheet(
  BuildContext context,
  Widget child, {
  bool short = false,
}) {
  final theme = Theme.of(context);
  final colors = context.mi;
  const padding = EdgeInsets.fromLTRB(
    MiSpace.lg,
    0,
    MiSpace.lg,
    MiSpace.xl,
  );
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.table,
    builder: (_) => Theme(
      data: theme,
      child: short
          ? SingleChildScrollView(padding: padding, child: child)
          : DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              maxChildSize: 0.95,
              builder: (context, controller) => SingleChildScrollView(
                controller: controller,
                padding: padding,
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
                // A little under the onboarding's 250, so the rows below
                // fit on the first screen.
                dimension: 210,
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
    // Laid out at least as wide as on the full-size card (inside its 250px
    // and padding), then shrunk to fit: a smaller card or large text scales
    // the scales down rather than cutting the poles off.
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: math.max(constraints.maxWidth, 214),
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

// ── Deine Themen ────────────────────────────────────────────────────────

/// A mirror of what the cards taught: the topics the feed shows more often,
/// strongest first. The cards steer it by what the user opens, does and
/// throws away; here a topic can only be forgotten.
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
            'Was du auf den Karten öffnest und erledigst, zeigen wir dir '
            'häufiger. Diese Themen stehen dann hier.',
            style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
          )
        else ...[
          Text(
            'Diese Themen zeigen wir dir öfter. Mit × vergisst du eins.',
            style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
          ),
          const SizedBox(height: MiSpace.base),
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
      // Filled, not outlined: a soft tint of the on-table colour reads on
      // both tables without a line around it.
      backgroundColor: colors.onTable.withValues(alpha: 0.07),
      surfaceTintColor: Colors.transparent,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: MiFonts.text,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: colors.onTable,
      ),
    );
  }
}
