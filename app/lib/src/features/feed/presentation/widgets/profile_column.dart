import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../domain/interest_config.dart';
import '../../domain/interest_weights.dart';
import '../../domain/lebenslage.dart';
import '../../domain/topic_tags.g.dart';
import '../../domain/user_profile.dart';
import 'axis_track.dart';
import 'interest_chips.dart';
import 'lebenslagen_picker.dart';

/// The Profil tab on the card table: the user's values, what matters to
/// them and their topics, as sections on the table divided by keylines.
/// Only what is set shows here; the full lists open in a sheet.
class ProfileColumn extends StatelessWidget {
  const ProfileColumn({
    required this.profile,
    required this.onEdit,
    required this.onLebenslagenChanged,
    required this.onInterestsChanged,
    super.key,
  });

  final UserProfile? profile;
  final VoidCallback onEdit;
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
          child: _ValuesSection(profile: p, onEdit: onEdit),
        ),
        if (p != null) ...[
          _Section(
            child: _LebenslagenSection(
              selected: p.lebenslagen,
              onChanged: onLebenslagenChanged,
            ),
          ),
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
  const _Section({required this.child, this.first = false});

  final Widget child;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        MiSpace.lg,
        first ? 0 : MiSpace.lg,
        MiSpace.lg,
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
/// ausfüllen", "Themen anpassen").
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

// ── Deine Werte ─────────────────────────────────────────────────────────

/// One value axis with its two poles, worded like the answers in the
/// questionnaire: -2 is the left answer, +2 the right one.
class _Axis {
  const _Axis(this.name, this.left, this.right);

  final String name;
  final String left;
  final String right;
}

const _wirtschaft = _Axis('Wirtschaft', 'Umverteilung', 'Freier Markt');
const _diplomatie = _Axis('Diplomatie', 'National', 'International');
const _freiheit = _Axis('Freiheit', 'Bürgerrechte', 'Sicherheit');
const _wandel = _Axis('Wandel', 'Bewahren', 'Verändern');

class _ValuesSection extends StatelessWidget {
  const _ValuesSection({required this.profile, required this.onEdit});

  final UserProfile? profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final p = profile;
    final answered = p != null && p.answeredCount > 0;
    final axes = answered
        ? [
            (_wirtschaft, p.axisEqualityMarkets),
            (_diplomatie, p.axisNationGlobe),
            (_freiheit, p.axisLibertyAuthority),
            (_wandel, p.axisTraditionProgress),
          ]
        : const <(_Axis, double)>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Deine Werte'),
        const SizedBox(height: MiSpace.base),
        if (answered)
          for (var i = 0; i < axes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: MiSpace.md),
              child: _AxisBlock(
                axis: axes[i].$1,
                value: axes[i].$2,
                // The colour belongs to the axis, never to a side.
                face: colors.topics[i % colors.topics.length],
              ),
            )
        else ...[
          Text(
            'Noch nicht ausgefüllt.',
            style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
          ),
          const SizedBox(height: MiSpace.base),
        ],
        _OutlinedPill(
          label:
              answered ? 'Fragebogen erneut ausfüllen' : 'Fragebogen ausfüllen',
          onPressed: onEdit,
        ),
      ],
    );
  }
}

/// One axis as a coloured block: its name, both poles, and where the user
/// stands, with a bar from the centre to the marker showing how far they
/// lean. The marker slides out from the centre when the block first shows.
class _AxisBlock extends StatelessWidget {
  const _AxisBlock({
    required this.axis,
    required this.value,
    required this.face,
  });

  final _Axis axis;
  final double value; // -2.0 to +2.0
  final Color face;

  String get _reading {
    final v = value.clamp(-2.0, 2.0);
    if (v.abs() < 0.5) return 'ausgeglichen';
    final pole = v < 0 ? axis.left : axis.right;
    return v.abs() < 1.25 ? 'eher $pole' : 'klar $pole';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final ink = colors.onCard;
    final pole = text.labelMedium?.copyWith(
      color: ink,
      fontWeight: FontWeight.w800,
    );
    return Semantics(
      label: '${axis.name}: $_reading, zwischen ${axis.left} und '
          '${axis.right}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          MiSpace.base + 2,
          MiSpace.base,
          MiSpace.base + 2,
          MiSpace.base,
        ),
        decoration: BoxDecoration(
          color: face,
          borderRadius: BorderRadius.circular(MiRadius.card - 8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              axis.name,
              style: text.titleLarge?.copyWith(
                fontSize: 16,
                letterSpacing: -0.02 * 16,
                color: ink,
              ),
            ),
            const SizedBox(height: MiSpace.md),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.clamp(-2.0, 2.0) / 2),
              duration:
                  MiMotion.reduced(context) ? Duration.zero : MiMotion.flight,
              curve: MiMotion.ease,
              builder: (context, t, _) =>
                  AxisTrack(position: t, ink: ink, stock: colors.cardStock),
            ),
            const SizedBox(height: MiSpace.sm),
            Row(
              children: [
                Expanded(child: Text(axis.left, style: pole)),
                const SizedBox(width: MiSpace.sm),
                Expanded(
                  child: Text(
                    axis.right,
                    style: pole,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dir wichtig ─────────────────────────────────────────────────────────

/// The picked public Lebenslagen; the picker opens in a sheet. Private ones
/// are left out of the overview (the picker itself shows them, it is where
/// they are edited).
class _LebenslagenSection extends StatelessWidget {
  const _LebenslagenSection({required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  void _edit(BuildContext context) {
    var current = selected;
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
    final shown = [
      for (final id in selected)
        if (lebenslageById[id] case final item? when !item.isPrivate) item,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          'Dir wichtig',
          action: 'Bearbeiten',
          onAction: () => _edit(context),
        ),
        const SizedBox(height: MiSpace.sm),
        if (shown.isEmpty)
          Text(
            selected.isEmpty
                ? 'Noch nichts ausgewählt. Damit zeigen wir dir passendere '
                    'Themen.'
                : 'Deine Auswahl ist gespeichert.',
            style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
          )
        else
          Wrap(
            spacing: MiSpace.sm,
            runSpacing: MiSpace.sm,
            children: [for (final item in shown) _TableChip(item.label)],
          ),
      ],
    );
  }
}

/// A read-only pill on the table, like the kind chips in Wirkung.
class _TableChip extends StatelessWidget {
  const _TableChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MiSpace.md,
        vertical: MiSpace.xs + 2,
      ),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: colors.onTableMuted)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

// ── Deine Themen ────────────────────────────────────────────────────────

/// Only the topics that steer the feed: set to mehr or weniger, or learned.
/// Every topic is one tap away in a sheet.
class _TopicsSection extends StatelessWidget {
  const _TopicsSection({required this.interests, required this.onChanged});

  final InterestWeights interests;
  final ValueChanged<InterestWeights> onChanged;

  static const _config = InterestConfig();

  void _edit(BuildContext context) {
    var current = interests;
    _showTableSheet(
      context,
      StatefulBuilder(
        builder: (context, setSheetState) => InterestChips(
          interests: current,
          onChanged: (next) {
            setSheetState(() => current = next);
            onChanged(next);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    bool learned(String tag) =>
        interests.learnedOf(tag, now, _config) >= _config.reasonThreshold;
    int rank(String tag) => switch (interests.manual[tag]) {
          InterestLevel.more => 0,
          InterestLevel.less => 2,
          null => 1,
        };
    final active = [
      for (final tag in kTopicTags)
        if (interests.manual[tag] != null || learned(tag)) tag,
    ]..sort((a, b) => rank(a).compareTo(rank(b)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          'Deine Themen',
          action: 'Anpassen',
          onAction: () => _edit(context),
        ),
        const SizedBox(height: MiSpace.sm),
        if (active.isEmpty)
          Text(
            'Noch nichts eingestellt. Dein Feed lernt aus dem, was du '
            'öffnest.',
            style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
          )
        else
          Wrap(
            spacing: MiSpace.sm,
            runSpacing: MiSpace.sm,
            children: [
              for (final tag in active)
                TopicChip(
                  tag: tag,
                  level: interests.manual[tag],
                  learned: learned(tag),
                  onTap: () => onChanged(
                    interests.withManual(
                      tag,
                      InterestChips.next(interests.manual[tag]),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
