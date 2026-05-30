import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/civic_action.dart';
import 'action_tile.dart';
import 'app_colors.dart';
import 'shared_widgets.dart';

class RecommendationPanel extends StatelessWidget {
  const RecommendationPanel({
    required this.l10n,
    required this.recommendations,
    super.key,
  });

  final AppLocalizations l10n;
  final List<ActionRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: AppColors.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RecommendationHeader(
            l10n: l10n,
            count: recommendations.length,
          ),
          const SizedBox(height: 16),
          const ProgressLine(value: 0.56),
          const SizedBox(height: 18),
          if (recommendations.isEmpty)
            _EmptyState(l10n: l10n)
          else
            for (final recommendation in recommendations) ...[
              ActionTile(
                l10n: l10n,
                recommendation: recommendation,
              ),
              if (recommendation != recommendations.last) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _RecommendationHeader extends StatelessWidget {
  const _RecommendationHeader({
    required this.l10n,
    required this.count,
  });

  final AppLocalizations l10n;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.feedGreeting,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                l10n.recommendationsForCount(count),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.mutedText,
                    ),
              ),
            ],
          ),
        ),
        StatusBadge(label: l10n.activeStreak),
      ],
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
