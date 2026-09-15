import 'package:flutter/material.dart';

import '../feed/presentation/widgets/app_colors.dart';
import '../feed/presentation/widgets/components/surface_card.dart';
import '../feed/presentation/widgets/components/text_badges.dart';

/// "Wirkung" tab — mockup only, no backend call. Shows what this screen
/// will eventually do (track vote outcomes, petition quorums, MdB replies
/// after a user acts) without inventing fake numbers to pretend it's live
/// data — an honest "coming soon" preview, one example row clearly marked
/// as an example rather than a real tracked outcome.
class WirkungTab extends StatelessWidget {
  const WirkungTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          color: AppColors.surface,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wirkung',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hier siehst du bald Abstimmungsergebnisse, Petitionsquoren '
                'und Antworten deiner Abgeordneten. Dieser Bereich ist noch '
                'nicht angebunden.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.mutedText,
                      height: 1.3,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionLabel(label: 'Beispielansicht'),
        const SizedBox(height: 10),
        const Opacity(
          opacity: 0.55,
          child: _ExampleOutcomeCard(),
        ),
      ],
    );
  }
}

class _ExampleOutcomeCard extends StatelessWidget {
  const _ExampleOutcomeCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: AppColors.surfaceMuted,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.mutedText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Beispiel: Brief an MdB verschickt',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.mutedText,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Später erscheint hier, ob und wie deine Abgeordnete '
                  'geantwortet hat.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedText,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
