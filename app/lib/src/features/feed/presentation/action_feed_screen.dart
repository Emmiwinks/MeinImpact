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
    super.key,
  });

  final ActionRepository actionRepository;
  final Locale selectedLocale;
  final ValueChanged<Locale> onLocaleChanged;

  static const _defaultProfile = UserProfile(
    topics: ['climate', 'housing', 'democracy'],
    valueAxes: {'civil_rights': 2},
    region: 'Germany',
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: FutureBuilder<List<ActionRecommendation>>(
        future: actionRepository.recommendations(_defaultProfile),
        builder: (context, snapshot) {
          return AppFrame(
            l10n: l10n,
            selectedLocale: selectedLocale,
            onLocaleChanged: onLocaleChanged,
            child: _buildContent(l10n, snapshot),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    AppLocalizations l10n,
    AsyncSnapshot<List<ActionRecommendation>> snapshot,
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
    );
  }
}
