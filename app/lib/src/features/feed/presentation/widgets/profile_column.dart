import 'package:flutter/material.dart';

import '../../domain/user_profile.dart';
import 'app_colors.dart';
import 'components/surface_card.dart';
import 'components/text_badges.dart';

class ProfileColumn extends StatelessWidget {
  const ProfileColumn({
    required this.profile,
    required this.onEdit,
    super.key,
  });

  final UserProfile? profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileCard(profile: profile, onEdit: onEdit),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onEdit});

  final UserProfile? profile;
  final VoidCallback onEdit;

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
            _AxisBar(label: 'Wirtschaft', value: p.axisWirtschaft),
            const SizedBox(height: 6),
            _AxisBar(label: 'Diplomatie', value: p.axisDiplomatie),
            const SizedBox(height: 6),
            _AxisBar(label: 'Freiheit', value: p.axisFreiheit),
            const SizedBox(height: 6),
            _AxisBar(label: 'Wandel', value: p.axisWandel),
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
                'Profil bearbeiten',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
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

