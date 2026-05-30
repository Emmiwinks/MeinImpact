import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../domain/action_repository.dart';
import '../domain/civic_action.dart';
import '../domain/user_profile.dart';

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
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          _LanguageMenu(
            selectedLocale: selectedLocale,
            onLocaleChanged: onLocaleChanged,
          ),
        ],
      ),
      body: FutureBuilder<List<ActionRecommendation>>(
        future: actionRepository.recommendations(_defaultProfile),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _FeedError(message: snapshot.error.toString());
          }
          final recommendations = snapshot.data ?? const [];
          return _RecommendationList(recommendations: recommendations);
        },
      ),
    );
  }
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({
    required this.selectedLocale,
    required this.onLocaleChanged,
  });

  final Locale selectedLocale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.languageMenuLabel,
      button: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Locale>(
            key: const Key('languageSelector'),
            value: selectedLocale,
            icon: const Icon(Icons.language),
            onChanged: (locale) {
              if (locale != null) {
                onLocaleChanged(locale);
              }
            },
            items: [
              DropdownMenuItem(
                value: const Locale('en'),
                child: Text(l10n.languageEnglish),
              ),
              DropdownMenuItem(
                value: const Locale('de'),
                child: Text(l10n.languageGerman),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationList extends StatelessWidget {
  const _RecommendationList({required this.recommendations});

  final List<ActionRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (recommendations.isEmpty) {
      return Center(child: Text(l10n.noActionsAvailable));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        return _ActionCard(recommendation: recommendations[index]);
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: recommendations.length,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.recommendation});

  final ActionRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final action = recommendation.action;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(action.summary),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(l10n.effortMinutes(action.effortMinutes))),
                Chip(label: Text(l10n.scoreLabel(recommendation.score))),
                for (final topic in action.topics) Chip(label: Text(topic)),
              ],
            ),
            const SizedBox(height: 12),
            Text(action.impactHint),
          ],
        ),
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l10n.recommendationsLoadError(message)),
      ),
    );
  }
}
