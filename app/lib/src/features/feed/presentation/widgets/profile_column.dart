import 'package:flutter/material.dart';

import '../../domain/lebenslage.dart';
import '../../domain/user_profile.dart';
import 'app_colors.dart';
import 'lebenslagen_picker.dart';
import 'components/surface_card.dart';
import 'components/text_badges.dart';

class ProfileColumn extends StatelessWidget {
  const ProfileColumn({
    required this.profile,
    required this.onEdit,
    required this.onLebenslagenChanged,
    super.key,
  });

  final UserProfile? profile;
  final VoidCallback onEdit;
  final ValueChanged<Set<String>> onLebenslagenChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileCard(
          profile: profile,
          onEdit: onEdit,
          onLebenslagenChanged: onLebenslagenChanged,
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onEdit,
    required this.onLebenslagenChanged,
  });

  final UserProfile? profile;
  final VoidCallback onEdit;
  final ValueChanged<Set<String>> onLebenslagenChanged;

  @override
  Widget build(BuildContext context) {
    final p = profile;

    return SurfaceCard(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MeinImpact',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Dein wöchentlicher Beitrag zur Demokratie.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedText,
                ),
          ),
          if (p != null && p.answeredCount > 0) ...[
            const SizedBox(height: 20),
            SectionLabel(label: 'Deine Werte'),
            const SizedBox(height: 10),
            _AxisBar(label: 'Wirtschaft', value: p.axisEqualityMarkets),
            const SizedBox(height: 6),
            _AxisBar(label: 'Diplomatie', value: p.axisNationGlobe),
            const SizedBox(height: 6),
            _AxisBar(label: 'Freiheit', value: p.axisLibertyAuthority),
            const SizedBox(height: 6),
            _AxisBar(label: 'Wandel', value: p.axisTraditionProgress),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 42,
            child: OutlinedButton(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: AppColors.subtleBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Fragebogen erneut ausfüllen',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
          if (p != null) ...[
            const SizedBox(height: 24),
            _LebenslagenSection(
              selected: p.lebenslagen,
              onChanged: onLebenslagenChanged,
            ),
          ],
        ],
      ),
    );
  }
}

/// The profile overview of what matters to the user, with the picker behind
/// "Bearbeiten". Private Lebenslagen are left out of the overview (the
/// picker itself shows them, it is where they are edited).
class _LebenslagenSection extends StatefulWidget {
  const _LebenslagenSection({required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_LebenslagenSection> createState() => _LebenslagenSectionState();
}

class _LebenslagenSectionState extends State<_LebenslagenSection> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LebenslagenPicker(
            selected: widget.selected,
            onChanged: widget.onChanged,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _editing = false),
              child: const Text('Fertig'),
            ),
          ),
        ],
      );
    }
    final shown = [
      for (final id in widget.selected)
        if (lebenslageById[id] case final item? when !item.isPrivate) item,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel(label: 'Dir wichtig')),
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: const Text('Bearbeiten'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (shown.isEmpty)
          Text(
            widget.selected.isEmpty
                ? 'Noch nichts ausgewählt. Damit zeigen wir dir passendere '
                    'Themen.'
                : 'Deine Auswahl ist gespeichert.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.mutedText),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final item in shown) MetaChip(label: item.label)],
          ),
      ],
    );
  }
}

class _AxisBar extends StatelessWidget {
  const _AxisBar({required this.label, required this.value});

  final String label;
  final double value; // -2.0 to +2.0

  @override
  Widget build(BuildContext context) {
    // Normalise to 0–1 for the bar (0 = full left, 0.5 = centre, 1 = full right)
    final fill = ((value + 2) / 4).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedText,
                  fontSize: 11,
                ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.subtleBorder,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // Centre line
                  Positioned(
                    left: constraints.maxWidth / 2 - 1,
                    child: Container(
                      width: 2,
                      height: 6,
                      color: AppColors.border,
                    ),
                  ),
                  // Value indicator
                  Positioned(
                    left: (constraints.maxWidth * fill - 5).clamp(
                      0,
                      constraints.maxWidth - 10,
                    ),
                    child: Container(
                      width: 10,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
