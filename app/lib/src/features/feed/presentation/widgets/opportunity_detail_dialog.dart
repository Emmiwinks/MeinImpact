import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/opportunity_relevance_ranker.dart';
import '../../domain/opportunity.dart';
import 'app_colors.dart';
import 'components/surface_card.dart';
import 'components/text_badges.dart';
import 'pros_cons_expansion.dart';

/// Opened from a feed tile. One opportunity, one view; everything needed is
/// already in the pool response, so opening makes no network request. The
/// call to action deep-links to the registry, where the participation
/// itself happens.
class OpportunityDetailDialog extends StatelessWidget {
  const OpportunityDetailDialog({
    required this.l10n,
    required this.ranked,
    this.onActed,
    super.key,
  });

  final AppLocalizations l10n;
  final RankedOpportunity ranked;
  // Called when the user follows the call to action to the registry.
  final VoidCallback? onActed;

  Future<void> _openSource() async {
    final uri = Uri.tryParse(ranked.opportunity.sourceUrl);
    if (uri == null) return;
    onActed?.call();
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final opportunity = ranked.opportunity;
    final daysLeft = opportunity.daysLeft(DateTime.now());
    final place = opportunity.organizer ?? opportunity.locality;

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
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        MetaChip(label: opportunity.sourceOrg),
                        MetaChip(label: opportunity.kind.label),
                        if (place != null) MetaChip(label: place),
                        for (final district in opportunity.districts)
                          MetaChip(label: district),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      opportunity.title,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                height: 1.08,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      opportunity.summary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.mutedText,
                            height: 1.3,
                          ),
                    ),
                    if (ranked.matchedSnippet != null ||
                        daysLeft != null ||
                        opportunity.supportCount != null ||
                        opportunity.isAnnounced) ...[
                      const SizedBox(height: 12),
                      _PersonalRelevanceSection(
                        matchedSnippet: ranked.matchedSnippet,
                        facts: _facts(opportunity, daysLeft),
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
                    _PrimaryButton(
                      label: opportunity.kind.callToAction,
                      onPressed: _openSource,
                    ),
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

/// Registry facts as short chips: start date of announced procedures, days
/// left, and support (with its goal when the registry has one). Support is
/// informational only, never a ranking claim.
List<String> _facts(Opportunity opportunity, int? daysLeft) {
  final opensOn = opportunity.opensOn;
  final support = opportunity.supportCount;
  final goal = opportunity.supportGoal;
  return [
    if (opportunity.isAnnounced && opensOn != null)
      'Ab ${opensOn.day}.${opensOn.month}.${opensOn.year}',
    if (daysLeft != null) daysLeft == 0 ? 'Endet heute' : 'Noch $daysLeft Tage',
    if (support != null)
      goal != null
          ? '$support von $goal Unterstützer:innen'
          : '$support Unterstützer:innen',
  ];
}

/// The matched personal-impact snippet plus the registry fact chips.
class _PersonalRelevanceSection extends StatelessWidget {
  const _PersonalRelevanceSection({
    required this.matchedSnippet,
    required this.facts,
  });

  final String? matchedSnippet;
  final List<String> facts;

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
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final fact in facts) _KpiChip(label: fact)],
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
