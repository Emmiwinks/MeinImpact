import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/opportunity_relevance_ranker.dart';
import '../../domain/opportunity.dart';
import 'app_colors.dart';
import 'components/surface_card.dart';
import 'components/text_badges.dart';
import 'pros_cons_expansion.dart';

/// Opened from a feed tile. One opportunity, one view — no more topic/
/// option drill-down (de-duplication already happened server-side, so
/// there's nothing left to pick between). Everything needed is already in
/// the pool response; no follow-up network request on open.
class OpportunityDetailDialog extends StatelessWidget {
  const OpportunityDetailDialog({
    required this.l10n,
    required this.ranked,
    super.key,
  });

  final AppLocalizations l10n;
  final RankedOpportunity ranked;

  Future<void> _openSource() async {
    final uri = Uri.tryParse(ranked.opportunity.sourceUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final opportunity = ranked.opportunity;
    final cta = ActionCta.forOpportunity(opportunity);
    final daysLeft = opportunity.deadline?.difference(DateTime.now()).inDays;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SingleChildScrollView(
              child: SurfaceCard(
                key: ValueKey('opportunity-${opportunity.id}'),
                color: AppColors.surface,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MetaChip(label: opportunity.sourceOrg),
                    const SizedBox(height: 10),
                    Text(
                      opportunity.plainLanguageTitle,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                height: 1.08,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      opportunity.plainLanguageSummary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.mutedText,
                            height: 1.3,
                          ),
                    ),
                    if (ranked.matchedSnippet != null ||
                        (daysLeft != null && daysLeft >= 0) ||
                        opportunity.supportCount != null) ...[
                      const SizedBox(height: 12),
                      _PersonalRelevanceSection(
                        matchedSnippet: ranked.matchedSnippet,
                        daysLeft: daysLeft,
                        supportCount: opportunity.supportCount,
                      ),
                    ],
                    if (opportunity.affectedTags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in opportunity.affectedTags)
                            Pill(label: tag, color: AppColors.blueText),
                        ],
                      ),
                    ],
                    if (opportunity.proArgumente.isNotEmpty ||
                        opportunity.contraArgumente.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ProsConsExpansion(
                        prosTitle: l10n.prosTitle,
                        consTitle: l10n.consTitle,
                        pros: opportunity.proArgumente,
                        cons: opportunity.contraArgumente,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _PrimaryButton(label: cta.label, onPressed: _openSource),
                  ],
                ),
              ),
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
}

/// Real computed/observed facts only: the matched personal-impact
/// snippet, a genuine deadline countdown, and an opportunistic support
/// count — never a ranking claim (see rebuild plan section 6: support
/// count is informational only, never used to sort).
class _PersonalRelevanceSection extends StatelessWidget {
  const _PersonalRelevanceSection({
    required this.matchedSnippet,
    required this.daysLeft,
    required this.supportCount,
  });

  final String? matchedSnippet;
  final int? daysLeft;
  final int? supportCount;

  @override
  Widget build(BuildContext context) {
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
            'WAS BEDEUTET DAS FÜR DICH',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
          if ((daysLeft != null && daysLeft! >= 0) || supportCount != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (daysLeft != null && daysLeft! >= 0)
                  _KpiChip(
                    label:
                        daysLeft == 0 ? 'Heute Frist' : 'Noch $daysLeft Tage',
                  ),
                if (supportCount != null)
                  _KpiChip(label: '$supportCount Unterstützer:innen'),
              ],
            ),
          ],
          if (matchedSnippet != null) ...[
            const SizedBox(height: 8),
            Text(
              matchedSnippet!,
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

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
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
