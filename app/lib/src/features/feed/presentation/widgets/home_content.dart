import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/civic_action.dart';
import 'feed_column.dart';
import 'profile_column.dart';

class HomeContent extends StatelessWidget {
  const HomeContent({
    required this.l10n,
    required this.recommendations,
    super.key,
  });

  final AppLocalizations l10n;
  final List<ActionRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: ProfileColumn(l10n: l10n),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 6,
                child: FeedColumn(
                  l10n: l10n,
                  recommendations: recommendations,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            ProfileColumn(l10n: l10n),
            const SizedBox(height: 18),
            FeedColumn(
              l10n: l10n,
              recommendations: recommendations,
            ),
          ],
        );
      },
    );
  }
}
