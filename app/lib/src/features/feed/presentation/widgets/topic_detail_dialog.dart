import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/action_repository.dart';
import '../../domain/civic_action.dart';
import '../../domain/topic.dart';
import '../../domain/user_profile.dart';
import 'action_draft_preview.dart';
import 'app_colors.dart';
import 'components/surface_card.dart';
import 'topic_tile.dart';

/// Opened from a topic tile. Shows the topic overview (title/summary,
/// expandable pro/contra) and its options (petition, letter) unranked —
/// picking one drills into the existing `ActionDetailCard` for that
/// specific option, with a way back to the option list.
class TopicDetailDialog extends StatefulWidget {
  const TopicDetailDialog({
    required this.l10n,
    required this.topic,
    required this.profile,
    required this.repository,
    super.key,
  });

  final AppLocalizations l10n;
  final Topic topic;
  final UserProfile profile;
  final ActionRepository repository;

  @override
  State<TopicDetailDialog> createState() => _TopicDetailDialogState();
}

class _TopicDetailDialogState extends State<TopicDetailDialog> {
  ActionRecommendation? _selected;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SingleChildScrollView(
              child: _selected == null ? _buildOverview() : _buildOption(),
            ),
            Positioned(
              top: -12,
              right: -12,
              child: _CloseButton(onTap: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverview() {
    final topic = widget.topic;
    return SurfaceCard(
      key: ValueKey('topic-${topic.topicId}'),
      color: AppColors.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            topic.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.08,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            topic.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText,
                  height: 1.3,
                ),
          ),
          if (topic.reasons.isNotEmpty ||
              topic.werteMatchPercent != null ||
              topic.deadline != null) ...[
            const SizedBox(height: 12),
            _WhyInFeedSection(topic: topic),
          ],
          if (topic.proArgumente.isNotEmpty ||
              topic.contraArgumente.isNotEmpty) ...[
            const SizedBox(height: 8),
            ProsConsExpansion(
              prosTitle: widget.l10n.prosTitle,
              consTitle: widget.l10n.consTitle,
              pros: topic.proArgumente,
              cons: topic.contraArgumente,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Optionen',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: 8),
          for (final option in topic.options) ...[
            _OptionRow(
              option: option,
              onTap: () => setState(() => _selected = option),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildOption() {
    final option = _selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.topic.options.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton.icon(
              onPressed: () => setState(() => _selected = null),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Alle Optionen'),
              style: TextButton.styleFrom(foregroundColor: AppColors.mutedText),
            ),
          ),
        ActionDetailCard(
          key: ValueKey(option.action.id),
          l10n: widget.l10n,
          recommendation: option,
          profile: widget.profile,
          repository: widget.repository,
        ),
      ],
    );
  }
}

/// "Why is this in your feed" — moved here from the feed list (one tap
/// away, not list noise) per-user relevance, only real computed facts:
/// the device-side value-match KPI and, only for a genuine petition
/// deadline (never a letter's murky "latest document date"), a day count.
class _WhyInFeedSection extends StatelessWidget {
  const _WhyInFeedSection({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final daysLeft = topic.deadline?.difference(DateTime.now()).inDays;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WARUM DAS FÜR DICH IM FEED STEHT',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
          if (topic.werteMatchPercent != null ||
              (daysLeft != null && daysLeft >= 0)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (topic.werteMatchPercent != null)
                  _KpiChip(label: '${topic.werteMatchPercent}% Wertematch'),
                if (daysLeft != null && daysLeft >= 0)
                  _KpiChip(
                    label:
                        daysLeft == 0 ? 'Heute Frist' : 'Noch $daysLeft Tage',
                  ),
              ],
            ),
          ],
          if (topic.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              topic.reasons.join(' · '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.ink,
                    height: 1.25,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.phoneSurface,
        border: Border.all(color: AppColors.subtleBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option, required this.onTap});

  final ActionRecommendation option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = optionKindOf(option.action);
    final accent = engagementStateColor(option.action.engagementState);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.phoneSurface,
          border: Border.all(color: AppColors.subtleBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              kind == OptionKind.petition
                  ? Icons.fact_check_outlined
                  : Icons.mail_outline_rounded,
              color: accent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind == OptionKind.petition
                        ? 'Petition unterschreiben'
                        : 'Brief schreiben',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (option.action.stateReason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        option.action.stateReason!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.mutedText,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.mutedText),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.close, size: 20),
        ),
      ),
    );
  }
}
