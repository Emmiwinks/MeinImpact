import 'package:flutter/material.dart';

import '../../data/opportunity_relevance_ranker.dart';
import 'app_colors.dart';

/// One opportunity on the feed. Real, sourced facts only — no invented
/// score/effort/state chips (the old engagementState pill had no
/// replacement after the DIP-to-Tavily pivot, see
/// project_dip_to_tavily_pivot.md; nothing here pretends otherwise). The
/// only "extra" signals shown (deadline countdown, top-match emphasis) are
/// derived straight from real fields already on `Opportunity`/`ranked`.
class OpportunityTile extends StatelessWidget {
  const OpportunityTile({
    required this.ranked,
    required this.onTap,
    this.isSelected = false,
    this.isTopMatch = false,
    super.key,
  });

  final RankedOpportunity ranked;
  final VoidCallback onTap;
  final bool isSelected;
  // True only for the first tile AND when it has an actual personal-impact
  // match — a purely positional #1 (no match, just highest werte-alignment
  // fallback) does not get the emphasis treatment.
  final bool isTopMatch;

  @override
  Widget build(BuildContext context) {
    final opportunity = ranked.opportunity;
    final hook = ranked.matchedSnippet ?? opportunity.plainLanguageSummary;
    final source = _sourceStyle(opportunity.sourceOrg);
    final daysLeft = opportunity.deadline?.difference(DateTime.now()).inDays;
    final showDeadline = daysLeft != null && daysLeft >= 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isTopMatch ? AppColors.greenWash : AppColors.phoneSurface,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(color: AppColors.green, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: source.color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 15, 15, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(source.icon, size: 15, color: source.color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              opportunity.sourceOrg,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: source.color,
                                    fontWeight: FontWeight.w800,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (showDeadline) ...[
                            const SizedBox(width: 6),
                            _DeadlineBadge(daysLeft: daysLeft),
                          ],
                        ],
                      ),
                      if (isTopMatch) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: AppColors.greenDark,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'PASST ZU DIR',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: AppColors.greenDark,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        opportunity.plainLanguageTitle,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.12,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hook,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: ranked.matchedSnippet != null
                                  ? AppColors.greenDark
                                  : AppColors.mutedText,
                              fontWeight: ranked.matchedSnippet != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              height: 1.25,
                            ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeadlineBadge extends StatelessWidget {
  const _DeadlineBadge({required this.daysLeft});
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warmSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        daysLeft == 0 ? 'heute' : '${daysLeft}T',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.amberText,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _SourceStyle {
  const _SourceStyle(this.color, this.icon);
  final Color color;
  final IconData icon;
}

// Reuses the app's existing 3-color accent palette (green/blue/amber)
// instead of introducing new brand colors — keyed to the backend's known
// source orgs (tavily_opportunity_adapter.py's _SOURCE_ORG_NAMES), with a
// neutral fallback for anything new.
_SourceStyle _sourceStyle(String sourceOrg) => switch (sourceOrg) {
      'openPetition' => const _SourceStyle(
          AppColors.green,
          Icons.how_to_vote_outlined,
        ),
      'WeAct/Campact' => const _SourceStyle(
          AppColors.blueText,
          Icons.campaign_outlined,
        ),
      'Beteiligungsportal Sachsen' => const _SourceStyle(
          AppColors.amberText,
          Icons.forum_outlined,
        ),
      'Sächsischer Landtag' => const _SourceStyle(
          AppColors.amberText,
          Icons.account_balance_outlined,
        ),
      'Landeshauptstadt Dresden' ||
      'Ratsinformationssystem Dresden' =>
        const _SourceStyle(
          AppColors.blueText,
          Icons.location_city_outlined,
        ),
      _ => const _SourceStyle(AppColors.mutedText, Icons.public_outlined),
    };
