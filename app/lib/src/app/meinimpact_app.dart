import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../features/feed/domain/action_repository.dart';
import '../features/feed/presentation/action_feed_screen.dart';

typedef ActionRepositoryFactory = ActionRepository Function(
  AppLocalizations l10n,
);

class MeinImpactApp extends StatefulWidget {
  const MeinImpactApp({
    required ActionRepository actionRepository,
    super.key,
  })  : _actionRepository = actionRepository,
        createActionRepository = null;

  const MeinImpactApp.localized({
    required this.createActionRepository,
    super.key,
  }) : _actionRepository = null;

  final ActionRepository? _actionRepository;
  final ActionRepositoryFactory? createActionRepository;

  @override
  State<MeinImpactApp> createState() => _MeinImpactAppState();
}

class _MeinImpactAppState extends State<MeinImpactApp> {
  Locale _locale = const Locale('de');

  void _setLocale(Locale locale) {
    if (_locale == locale) {
      return;
    }
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1FA37A),
        ).copyWith(
          surface: const Color(0xFFFFFCF7),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF7F0),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: const Color(0xFF28241F),
              displayColor: const Color(0xFF28241F),
            ),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return ActionFeedScreen(
            actionRepository: _actionRepository(l10n),
            selectedLocale: _locale,
            onLocaleChanged: _setLocale,
          );
        },
      ),
    );
  }

  ActionRepository _actionRepository(AppLocalizations l10n) {
    final createActionRepository = widget.createActionRepository;
    if (createActionRepository != null) {
      return createActionRepository(l10n);
    }
    return widget._actionRepository!;
  }
}
