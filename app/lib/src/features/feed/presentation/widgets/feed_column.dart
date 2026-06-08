import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/action_repository.dart';
import '../../domain/civic_action.dart';
import '../../domain/user_profile.dart';
import 'action_draft_preview.dart';
import 'recommendation_panel.dart';

class FeedColumn extends StatefulWidget {
  const FeedColumn({
    required this.l10n,
    required this.recommendations,
    required this.profile,
    required this.repository,
    super.key,
  });

  final AppLocalizations l10n;
  final List<ActionRecommendation> recommendations;
  final UserProfile profile;
  final ActionRepository repository;

  @override
  State<FeedColumn> createState() => _FeedColumnState();
}

class _FeedColumnState extends State<FeedColumn> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(FeedColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset selection when recommendations change
    if (oldWidget.recommendations != widget.recommendations) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final recs = widget.recommendations;
    final selected =
        recs.isEmpty ? null : recs[_selectedIndex.clamp(0, recs.length - 1)];

    return Column(
      children: [
        RecommendationPanel(
          l10n: widget.l10n,
          recommendations: recs,
          selectedIndex: _selectedIndex,
          onSelect: (i) => setState(() => _selectedIndex = i),
        ),
        if (selected != null) ...[
          const SizedBox(height: 16),
          ActionDetailCard(
            key: ValueKey(selected.action.id),
            l10n: widget.l10n,
            recommendation: selected,
            profile: widget.profile,
            repository: widget.repository,
          ),
        ],
      ],
    );
  }
}
