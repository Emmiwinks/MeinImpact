import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../core/profile/user_profile_store.dart';
import '../features/feed/domain/action_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/feed/presentation/action_feed_screen.dart';
import '../features/landing/landing_screen.dart';
import '../features/onboarding/demographic_screen.dart';
import '../features/onboarding/topic_selection_screen.dart';
import '../features/onboarding/value_profile_screen.dart';

class MeinImpactApp extends StatefulWidget {
  /// Direct constructor — bypasses onboarding (used in tests and demos).
  const MeinImpactApp({
    required ActionRepository actionRepository,
    super.key,
  })  : _actionRepository = actionRepository,
        _profileStore = null,
        _initialProfile = null;

  /// Production constructor — shows onboarding when no profile exists.
  const MeinImpactApp.withProfile({
    required ActionRepository actionRepository,
    required UserProfileStore profileStore,
    UserProfile? initialProfile,
    super.key,
  })  : _actionRepository = actionRepository,
        _profileStore = profileStore,
        _initialProfile = initialProfile;

  final ActionRepository _actionRepository;
  final UserProfileStore? _profileStore;
  final UserProfile? _initialProfile;

  @override
  State<MeinImpactApp> createState() => _MeinImpactAppState();
}

class _MeinImpactAppState extends State<MeinImpactApp> {
  Locale _locale = const Locale('de');
  UserProfile? _profile;
  bool _showLanding = true;
  // Onboarding steps: 0 = topics, 1 = values, 2 = demographics, 3 = feed
  int _onboardingStep = 0;
  List<String>? _pendingTopics;
  List<String>? _pendingBlacklist;
  Map<String, int>? _pendingWerte;

  @override
  void initState() {
    super.initState();
    _profile = widget._initialProfile;
  }

  void _setLocale(Locale locale) {
    if (_locale == locale) return;
    setState(() => _locale = locale);
  }

  Future<void> _onTopicsComplete(
    List<String> topics,
    List<String> blacklist,
  ) async {
    setState(() {
      _pendingTopics = topics;
      _pendingBlacklist = blacklist;
      _onboardingStep = 1;
    });
  }

  Future<void> _onWerteComplete(Map<String, int> werte) async {
    setState(() {
      _pendingWerte = werte;
      _onboardingStep = 2;
    });
  }

  Future<void> _onDemographicComplete(UserProfile? patch) async {
    final profile = UserProfile(
      topics: _pendingTopics!,
      blacklist: _pendingBlacklist!,
      werte: _pendingWerte!,
      plz: patch?.plz,
      mdbName: patch?.mdbName,
      mdbParty: patch?.mdbParty,
      mdbWahlkreis: patch?.mdbWahlkreis,
    );
    await widget._profileStore?.save(profile);
    setState(() => _profile = profile);
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
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // No profile store → tests / demo mode, go straight to feed
    if (widget._profileStore == null) {
      return ActionFeedScreen(
        actionRepository: widget._actionRepository,
        selectedLocale: _locale,
        onLocaleChanged: _setLocale,
      );
    }

    // Profile loaded → show feed
    if (_profile != null) {
      return ActionFeedScreen(
        actionRepository: widget._actionRepository,
        selectedLocale: _locale,
        onLocaleChanged: _setLocale,
        profile: _profile,
        onEditProfile: () => setState(() {
          _profile = null;
          _showLanding = false; // skip landing when re-editing
          _onboardingStep = 0;
          _pendingTopics = null;
          _pendingBlacklist = null;
          _pendingWerte = null;
        }),
      );
    }

    // First visit → show landing page
    if (_showLanding) {
      return LandingScreen(
        onStart: () => setState(() => _showLanding = false),
      );
    }

    // Onboarding step 0: topic selection
    if (_onboardingStep == 0) {
      return TopicSelectionScreen(onComplete: _onTopicsComplete);
    }

    // Onboarding step 1: value profile
    if (_onboardingStep == 1) {
      return ValueProfileScreen(onComplete: _onWerteComplete);
    }

    // Onboarding step 2: demographics (PLZ + MdB) — optional
    return DemographicScreen(
      onComplete: _onDemographicComplete,
      onLookupMdb: widget._actionRepository.lookupMdb,
    );
  }
}
