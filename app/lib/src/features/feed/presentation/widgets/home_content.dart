import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../../domain/action_repository.dart';
import '../../domain/civic_action.dart';
import '../../domain/user_profile.dart';
import 'feed_column.dart';
import 'profile_column.dart';

class HomeContent extends StatelessWidget {
  const HomeContent({
    required this.l10n,
    required this.recommendations,
    required this.profile,
    required this.repository,
    required this.onEditProfile,
    super.key,
  });

  final AppLocalizations l10n;
  final List<ActionRecommendation> recommendations;
  final UserProfile profile;
  final ActionRepository repository;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final profileColumn = ProfileColumn(
      profile: profile,
      onEdit: onEditProfile,
    );
    final feedColumn = FeedColumn(
      l10n: l10n,
      recommendations: recommendations,
      profile: profile,
      repository: repository,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 860) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: profileColumn),
              const SizedBox(width: 20),
              Expanded(flex: 6, child: feedColumn),
            ],
          );
        }
        return Column(
          children: [
            profileColumn,
            const SizedBox(height: 18),
            feedColumn,
          ],
        );
      },
    );
  }
}
