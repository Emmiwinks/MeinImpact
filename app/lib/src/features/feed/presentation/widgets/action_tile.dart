import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/civic_action.dart';
import 'action_type_helpers.dart';
import 'app_colors.dart';
import 'shared_widgets.dart';

class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.l10n,
    required this.recommendation,
    super.key,
  });

  final AppLocalizations l10n;
  final ActionRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final action = recommendation.action;
    final topic = action.topics.isEmpty
        ? l10n.actionTypeAction
        : action.topics.first;
    final accent = actionTypeColor(action.actionType);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.phoneSurface,
        border: Border.all(color: AppColors.subtleBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.greenWash,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  actionTypeIcon(action.actionType),
                  color: accent,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  action.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Pill(
                label: actionTypeLabel(l10n, action.actionType),
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            action.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText,
                  height: 1.25,
                ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SignalDots(score: recommendation.score),
              MetaChip(label: l10n.valueMeta(topic)),
              MetaChip(label: l10n.effortMinutes(action.effortMinutes)),
              MetaChip(label: l10n.scoreLabel(recommendation.score)),
            ],
          ),
        ],
      ),
    );
  }
}
