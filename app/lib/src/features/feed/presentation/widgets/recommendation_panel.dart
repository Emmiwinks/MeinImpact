import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/civic_action.dart';
import 'action_tile.dart';
import 'app_colors.dart';
import 'components/surface_card.dart';

class RecommendationPanel extends StatelessWidget {
  const RecommendationPanel({
    required this.l10n,
    required this.recommendations,
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  final AppLocalizations l10n;
  final List<ActionRecommendation> recommendations;
  final int selectedIndex;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: AppColors.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(l10n: l10n, count: recommendations.length),
          const SizedBox(height: 16),
          if (recommendations.isEmpty)
            _EmptyState(l10n: l10n)
          else
            for (int i = 0; i < recommendations.length; i++) ...[
              ActionTile(
                l10n: l10n,
                recommendation: recommendations[i],
                isSelected: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
              if (i < recommendations.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.l10n, required this.count});

  final AppLocalizations l10n;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      l10n.recommendationsForCount(count),
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.noActionsAvailable,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.noActionsHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText,
                ),
          ),
        ],
      ),
    );
  }
}
