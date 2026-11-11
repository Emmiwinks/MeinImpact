import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../data/opportunity_relevance_ranker.dart';
import 'action_card.dart';
import 'topic_art.dart';

/// Every open action, one per row, in the same order as the hand: best match
/// first. Picking one pops with its id, and the hand takes that card to the
/// front.
class AllActionsScreen extends StatelessWidget {
  const AllActionsScreen({required this.opportunities, super.key});

  final List<RankedOpportunity> opportunities;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.table,
      appBar: AppBar(
        backgroundColor: colors.table,
        foregroundColor: colors.onTable,
        surfaceTintColor: Colors.transparent,
        title: Text('Alle Aktionen', style: text.titleLarge),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: MiSpace.xl),
        itemCount: opportunities.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                MiSpace.lg,
                0,
                MiSpace.lg,
                MiSpace.md,
              ),
              child: Text(
                'Nach Passung sortiert, die besten zuerst. '
                'Tippe eine an, um sie auf die Hand zu nehmen.',
                style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
              ),
            );
          }
          return _Row(ranked: opportunities[index - 1]);
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.ranked});

  final RankedOpportunity ranked;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final opportunity = ranked.opportunity;
    final why = whyLine(ranked);
    return InkWell(
      onTap: () => Navigator.of(context).pop(opportunity.id),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: MiSpace.lg,
          vertical: MiSpace.base,
        ),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.keyline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardThumbnail(look: TopicLook.of(opportunity)),
            const SizedBox(width: MiSpace.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(opportunity.title, style: text.titleMedium),
                  if (why != null) ...[
                    const SizedBox(height: MiSpace.xs),
                    Text(
                      why,
                      style: text.bodyMedium?.copyWith(
                        color: colors.onTableMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: MiSpace.sm),
                  Text(
                    metaLine(opportunity, DateTime.now()),
                    style: text.labelMedium?.copyWith(
                      color: colors.onTableMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
