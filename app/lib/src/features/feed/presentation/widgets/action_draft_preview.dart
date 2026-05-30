import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/civic_action.dart';
import 'app_colors.dart';
import 'shared_widgets.dart';

class ActionDraftPreview extends StatelessWidget {
  const ActionDraftPreview({
    required this.l10n,
    required this.recommendation,
    super.key,
  });

  final AppLocalizations l10n;
  final ActionRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final action = recommendation.action;
    final reason = recommendation.reasons.isEmpty
        ? l10n.reasonFallback
        : recommendation.reasons.first;

    return SurfaceCard(
      color: AppColors.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label: l10n.aiSupportTitle),
          const SizedBox(height: 9),
          Text(
            action.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.08,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  value: l10n.peopleJoined,
                  icon: Icons.groups_2_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricCard(
                  value: l10n.averageTime,
                  icon: Icons.schedule_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InfoBox(
            title: l10n.whyNowTitle,
            body: reason,
            color: AppColors.surfaceMuted,
          ),
          const SizedBox(height: 10),
          InfoBox(
            title: l10n.whatItMeansTitle,
            body: action.impactHint,
            color: AppColors.greenWash,
          ),
          const SizedBox(height: 16),
          _PrimaryActionButton(label: l10n.editAndSend),
          const SizedBox(height: 9),
          _SecondaryActionButton(label: l10n.adoptDraft),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.subtleBorder),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
