import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../core/profile/user_profile_store.dart';
import '../features/feed/domain/action_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/onboarding/demographic_screen.dart';
import '../features/onboarding/value_profile_screen.dart';
import 'main_tab_screen.dart';

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
  UserProfile? _profile;
  // Onboarding steps: 0 = value profile, 1 = demographics, 2 = feed
  int _onboardingStep = 0;
  Map<String, int>? _pendingWerte;

  @override
  void initState() {
    super.initState();
    _profile = widget._initialProfile;
  }

  Future<void> _onWerteComplete(Map<String, int> werte) async {
    setState(() {
      _pendingWerte = werte;
      _onboardingStep = 1;
    });
  }

  Future<void> _onDemographicComplete(UserProfile? patch) async {
    final profile = UserProfile(
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
      // No language switcher — German only, matching the real user base.
      locale: const Locale('de'),
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
    // No profile store → tests / demo mode, go straight to the tab shell
    if (widget._profileStore == null) {
      return MainTabScreen(actionRepository: widget._actionRepository);
    }

    // Profile loaded → show the tab shell
    if (_profile != null) {
      return MainTabScreen(
        actionRepository: widget._actionRepository,
        profile: _profile,
        onEditProfile: () => setState(() {
          _profile = null;
          _onboardingStep = 0;
          _pendingWerte = null;
        }),
      );
    }

    // Onboarding step 0: value profile
    if (_onboardingStep == 0) {
      return ValueProfileScreen(onComplete: _onWerteComplete);
    }

    // Onboarding step 1: demographics (PLZ + MdB) — optional
    return DemographicScreen(
      onComplete: _onDemographicComplete,
      onLookupMdb: widget._actionRepository.lookupMdb,
    );
  }
}
