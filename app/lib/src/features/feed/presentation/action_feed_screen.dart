import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../domain/action_repository.dart';
import '../domain/civic_action.dart';
import '../domain/user_profile.dart';
import 'widgets/app_colors.dart';
import 'widgets/app_frame.dart';
import 'widgets/feed_error.dart';
import 'widgets/home_content.dart';
import 'widgets/loading_card.dart';

class ActionFeedScreen extends StatelessWidget {
  const ActionFeedScreen({
    required this.actionRepository,
    required this.selectedLocale,
    required this.onLocaleChanged,
    this.profile,
    this.onEditProfile,
    super.key,
  });

  final ActionRepository actionRepository;
  final Locale selectedLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final UserProfile? profile;
  final VoidCallback? onEditProfile;

  static const _fallbackProfile = UserProfile(
    topics: ['klimaschutz', 'demokratie'],
  );

  @override
  Widget build(BuildContext context) {
    final effectiveProfile = profile ?? _fallbackProfile;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: FutureBuilder<List<ActionRecommendation>>(
        future: actionRepository.recommendations(effectiveProfile),
        builder: (context, snapshot) {
          return AppFrame(
            l10n: l10n,
            selectedLocale: selectedLocale,
            onLocaleChanged: onLocaleChanged,
            child: _buildContent(
              context,
              l10n,
              snapshot,
              effectiveProfile,
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    AsyncSnapshot<List<ActionRecommendation>> snapshot,
    UserProfile effectiveProfile,
  ) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const LoadingCard();
    }
    if (snapshot.hasError) {
      return FeedError(message: snapshot.error.toString());
    }

    return HomeContent(
      l10n: l10n,
      recommendations: snapshot.data ?? const [],
      profile: effectiveProfile,
      repository: actionRepository,
      onEditProfile: onEditProfile ?? () {},
    );
  }
}
