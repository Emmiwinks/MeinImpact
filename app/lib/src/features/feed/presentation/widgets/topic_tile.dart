import 'package:flutter/material.dart';

import '../../domain/topic.dart';
import 'app_colors.dart';
import 'components/text_badges.dart';

/// Real, sourced facts only — no score/effort chips. `engagementState` is
/// an existential aggregate ("does ≥1 option have a live window right
/// now"), see topic.dart.
Color engagementStateColor(String state) => switch (state) {
      'A' => AppColors.green,
      'B' => AppColors.amberText,
      _ => AppColors.blueText,
    };

String engagementStateLabel(String state) => switch (state) {
      'A' => 'Entscheidung steht an',
      'B' => 'Positionen bilden sich',
      _ => 'Im öffentlichen Diskurs',
    };

class TopicTile extends StatelessWidget {
  const TopicTile({
    required this.topic,
    required this.onTap,
    this.isSelected = false,
    super.key,
  });

  final Topic topic;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final accent = engagementStateColor(topic.engagementState);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.greenWash : AppColors.phoneSurface,
          border: Border.all(
            color: isSelected ? AppColors.green : AppColors.subtleBorder,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    topic.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Pill(
                  label: engagementStateLabel(topic.engagementState),
                  color: accent,
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              topic.summary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mutedText,
                    height: 1.25,
                  ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (topic.stateReason != null) ...[
              const SizedBox(height: 8),
              Text(
                topic.stateReason!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            // "Why this is in your feed" (reasons, KPIs) is deliberately
            // NOT shown here — it's per-user relevance detail, one tap
            // away in TopicDetailDialog, not feed-list noise.
          ],
        ),
      ),
    );
  }
}
