import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../domain/interest_config.dart';
import '../../domain/interest_weights.dart';
import '../../domain/topic_tags.g.dart';

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
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final at = now ?? DateTime.now();
    final muted = text.bodyMedium?.copyWith(color: colors.onTableMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Deine Themen', style: text.titleLarge),
        const SizedBox(height: MiSpace.sm),
        Text.rich(
          TextSpan(
            style: muted,
            children: [
              const TextSpan(
                text: 'Tippe auf ein Thema: mehr, weniger oder normal. Dein '
                    'Feed lernt außerdem aus dem, was du öffnest (markiert '
                    'mit ',
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(
                  _learnedIcon,
                  size: 16,
                  color: colors.onTableMuted,
                  semanticLabel: 'Funkel-Symbol',
                ),
              ),
              const TextSpan(text: '). Ausgeblendet wird nie etwas.'),
            ],
          ),
        ),
        const SizedBox(height: MiSpace.md),
        Wrap(
          spacing: MiSpace.sm,
          runSpacing: MiSpace.sm,
          children: [
            for (final tag in kTopicTags)
              TopicChip(
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

const _learnedIcon = Icons.auto_awesome;

/// Normal: an outlined pill. Mehr: the amber "selected" fill with ink text.
/// Weniger: muted. The level is also spelled out, so it never rests on
/// colour alone.
class TopicChip extends StatelessWidget {
  const TopicChip({
    required this.tag,
    required this.level,
    required this.learned,
    required this.onTap,
    super.key,
  });

  final String tag;
  final InterestLevel? level;
  final bool learned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final more = level == InterestLevel.more;
    final less = level == InterestLevel.less;
    final foreground = more
        ? colors.onCard
        : less
            ? colors.onTableMuted
            : colors.onTable;
    final suffix = more
        ? ' · mehr'
        : less
            ? ' · weniger'
            : '';
    return ActionChip(
      key: ValueKey('topic-$tag'),
      avatar: learned ? Icon(_learnedIcon, size: 16, color: foreground) : null,
      label: Text('$tag$suffix'),
      onPressed: onTap,
      // Compact to look at; the padded tap target keeps 48dp.
      visualDensity: VisualDensity.compact,
      backgroundColor: more ? colors.topics[2] : Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: more
              ? colors.topics[2]
              : less
                  ? colors.keyline
                  : colors.onTableMuted,
        ),
      ),
      labelStyle: TextStyle(
        fontFamily: MiFonts.text,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: foreground,
      ),
    );
  }
}
