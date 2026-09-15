import 'package:flutter/material.dart';

import '../../domain/topic.dart';
import 'app_colors.dart';
import 'components/surface_card.dart';
import 'topic_tile.dart';

class TopicPanel extends StatelessWidget {
  const TopicPanel({
    required this.topics,
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  final List<Topic> topics;
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
          _Header(count: topics.length),
          const SizedBox(height: 16),
          if (topics.isEmpty)
            const _EmptyState()
          else
            for (int i = 0; i < topics.length; i++) ...[
              TopicTile(
                topic: topics[i],
                isSelected: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
              if (i < topics.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      count == 1 ? '1 Thema für dich' : '$count Themen für dich',
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
            'Noch keine Themen verfügbar.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Deine wöchentlichen Themen erscheinen hier, sobald passende '
            'öffentliche Aktionen verfügbar sind.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText,
                ),
          ),
        ],
      ),
    );
  }
}
