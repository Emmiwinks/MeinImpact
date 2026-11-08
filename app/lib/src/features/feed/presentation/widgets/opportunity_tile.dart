import 'package:flutter/material.dart';

import '../../data/opportunity_relevance_ranker.dart';
import '../../domain/lebenslage.dart';
import 'app_colors.dart';

/// One opportunity on the feed. Real, sourced facts only, no invented
/// scores: the registry, the kind of participation, a deadline countdown
/// from the registry's own end date, and top-match emphasis derived from
/// the on-device ranking.
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
    final hook = ranked.matchedSnippet ?? opportunity.summary;
    final source = _sourceStyle(opportunity.sourceOrg);
    final daysLeft = opportunity.daysLeft(DateTime.now());

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
        // The source-colored stripe is a left border clipped to the card's
        // radius, so the card sizes to its content without IntrinsicHeight
        // (which mis-measured fractional line heights by a pixel).
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: source.color, width: 4)),
            ),
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
                          '${opportunity.sourceOrg} · '
                          '${opportunity.kind.label}',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: source.color,
                                    fontWeight: FontWeight.w800,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (daysLeft != null) ...[
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
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
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
                    opportunity.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                  if (cardReason(ranked) case final reason?) ...[
                    const SizedBox(height: 8),
                    Text(
                      reason,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.mutedText,
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Why this card is up here, in one line: a picked Lebenslage first, then a
/// learned topic interest. A private Lebenslage is never named on a card.
String? cardReason(RankedOpportunity ranked) {
  final lebenslage = lebenslageById[ranked.matchedLebenslage];
  if (lebenslage != null) {
    return lebenslage.isPrivate
        ? 'Passt zu deinen Themen'
        : 'Passt zu deinen Themen: ${lebenslage.label}';
  }
  final tag = ranked.interestTag;
  return tag != null ? 'Weil du dich für $tag interessierst' : null;
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

// Reuses the app's 3-color accent palette (green/blue/amber), keyed to the
// backend's registry display names (`catalog.SOURCE_NAMES`), with a neutral
// fallback for registries added later.
_SourceStyle _sourceStyle(String sourceOrg) => switch (sourceOrg) {
      'openPetition' => const _SourceStyle(
          AppColors.green,
          Icons.how_to_vote_outlined,
        ),
      'WeAct' => const _SourceStyle(
          AppColors.blueText,
          Icons.campaign_outlined,
        ),
      'Beteiligungsportal Sachsen' => const _SourceStyle(
          AppColors.amberText,
          Icons.forum_outlined,
        ),
      'EU-Kommission: Ihre Meinung zählt' => const _SourceStyle(
          AppColors.blueText,
          Icons.account_balance_outlined,
        ),
      'Ratsinformationssystem Dresden' => const _SourceStyle(
          AppColors.green,
          Icons.gavel_outlined,
        ),
      _ => const _SourceStyle(AppColors.mutedText, Icons.public_outlined),
    };
