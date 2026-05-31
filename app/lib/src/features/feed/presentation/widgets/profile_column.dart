import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import 'app_colors.dart';
import 'shared_widgets.dart';

class ProfileColumn extends StatelessWidget {
  const ProfileColumn({required this.l10n, super.key});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileCard(l10n: l10n),
        const SizedBox(height: 16),
        _TrackingCard(l10n: l10n),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final topics = [
      _TopicSpec(l10n.topicClimate, Icons.eco_outlined, true),
      _TopicSpec(l10n.topicSocialJustice, Icons.favorite_border, true),
      _TopicSpec(l10n.topicDemocracy, Icons.how_to_vote_outlined, true),
      _TopicSpec(l10n.topicEducation, Icons.school_outlined, false),
      _TopicSpec(l10n.topicHealth, Icons.health_and_safety_outlined, false),
      _TopicSpec(l10n.topicEconomy, Icons.work_outline, true),
      _TopicSpec(l10n.topicHousing, Icons.home_outlined, false),
      _TopicSpec(l10n.topicDigitalization, Icons.devices_outlined, false),
    ];

    return SurfaceCard(
      color: AppColors.phoneSurface,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 58,
              height: 13,
              decoration: const BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.brandName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            l10n.appTagline,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedText,
                ),
          ),
          const SizedBox(height: 18),
          const ProgressLine(value: 0.28),
          const SizedBox(height: 20),
          SectionLabel(label: l10n.profileEyebrow),
          const SizedBox(height: 10),
          for (final topic in topics) ...[
            _TopicRow(topic: topic),
            const SizedBox(height: 7),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(l10n.profileButton),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicSpec {
  const _TopicSpec(this.label, this.icon, this.selected);

  final String label;
  final IconData icon;
  final bool selected;
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic});

  final _TopicSpec topic;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        topic.selected ? AppColors.green : AppColors.subtleBorder;
    final background =
        topic.selected ? AppColors.greenWash : AppColors.surfaceMuted;

    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            topic.icon,
            size: 16,
            color: topic.selected ? AppColors.greenDark : AppColors.ink,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              topic.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight:
                        topic.selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      color: AppColors.surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CheckMark(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.impactTrackingTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.impactTrackingBody,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mutedText,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TimelineRow(label: l10n.impactStepVote),
          const SizedBox(height: 9),
          TimelineRow(label: l10n.impactStepReply),
        ],
      ),
    );
  }
}
