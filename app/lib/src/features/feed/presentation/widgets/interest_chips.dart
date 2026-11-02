import 'package:flutter/material.dart';

import '../../domain/interest_config.dart';
import '../../domain/interest_weights.dart';
import '../../domain/topic_tags.g.dart';
import 'app_colors.dart';
import 'components/text_badges.dart';

/// "Deine Themen": every topic tag as a chip. A tap cycles normal -> mehr ->
/// weniger -> normal and sets a manual level (it never decays). Topics the
/// feed has learned on its own are marked, so a wrong guess can be seen and
/// corrected. Like the rest of the ranking, this only reorders the feed,
/// it never hides a topic.
class InterestChips extends StatelessWidget {
  const InterestChips({
    required this.interests,
    required this.onChanged,
    this.config = const InterestConfig(),
    this.now,
    super.key,
  });

  final InterestWeights interests;
  final ValueChanged<InterestWeights> onChanged;
  final InterestConfig config;
  // For tests; defaults to the current time.
  final DateTime? now;

  static InterestLevel? next(InterestLevel? level) => switch (level) {
        null => InterestLevel.more,
        InterestLevel.more => InterestLevel.less,
        InterestLevel.less => null,
      };

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(label: 'Deine Themen'),
        const SizedBox(height: 4),
        Text(
          'Tippe auf ein Thema: mehr, weniger oder normal. Dein Feed lernt '
          'außerdem aus dem, was du öffnest (markiert mit ✦). Ausgeblendet '
          'wird nie etwas.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in kTopicTags)
              _TopicChip(
                tag: tag,
                level: interests.manual[tag],
                learned: interests.learnedOf(tag, at, config) >=
                    config.reasonThreshold,
                onTap: () => onChanged(
                  interests.withManual(tag, next(interests.manual[tag])),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.tag,
    required this.level,
    required this.learned,
    required this.onTap,
  });

  final String tag;
  final InterestLevel? level;
  final bool learned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (suffix, color) = switch (level) {
      InterestLevel.more => (' · mehr', AppColors.greenDark),
      InterestLevel.less => (' · weniger', AppColors.mutedText),
      null => ('', AppColors.ink),
    };
    return ActionChip(
      key: ValueKey('topic-$tag'),
      label: Text('${learned ? '✦ ' : ''}$tag$suffix'),
      onPressed: onTap,
      backgroundColor:
          level == InterestLevel.more ? AppColors.greenWash : AppColors.surface,
      side: BorderSide(
        color: level == null ? AppColors.subtleBorder : color,
      ),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}
