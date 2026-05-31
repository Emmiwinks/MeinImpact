import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/civic_action.dart';
import 'action_draft_preview.dart';
import 'completion_preview.dart';
import 'recommendation_panel.dart';

class FeedColumn extends StatelessWidget {
  const FeedColumn({
    required this.l10n,
    required this.recommendations,
    super.key,
  });

  final AppLocalizations l10n;
  final List<ActionRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RecommendationPanel(
          l10n: l10n,
          recommendations: recommendations,
        ),
        if (recommendations.isNotEmpty) ...[
          const SizedBox(height: 16),
          ActionDraftPreview(
            l10n: l10n,
            recommendation: recommendations.first,
          ),
          const SizedBox(height: 16),
          CompletionPreview(l10n: l10n),
        ],
      ],
    );
  }
}
