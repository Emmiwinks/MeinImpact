import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../core/profile/user_profile_store.dart';
import '../features/feed/domain/betroffenheitsprofil.dart';
import '../features/feed/domain/opportunity_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/onboarding/demographic_screen.dart';
import '../features/onboarding/value_profile_screen.dart';
import 'main_tab_screen.dart';

/// Hardcoded stand-in for the Betroffenheitsprofil, used by the
/// "Beispiel-Profil übernehmen" onboarding shortcut. Deliberately not
/// configurable — it exists to skip setup, not to represent a real answer.
const _kExampleBetroffenheitsprofil = Betroffenheitsprofil(
  wohnsituation: Wohnsituation.mieter,
  oepnvNutzung: true,
  autoNutzung: false,
  hatKinder: false,
  erwerbsstatus: Erwerbsstatus.angestellt,
  pflegeBetroffen: false,
  migrationshintergrund: false,
);

class MeinImpactApp extends StatefulWidget {
  /// Direct constructor — bypasses onboarding (used in tests and demos).
  const MeinImpactApp({
    required OpportunityRepository opportunityRepository,
    super.key,
  })  : _opportunityRepository = opportunityRepository,
        _profileStore = null,
        _initialProfile = null;

  /// Production constructor — shows onboarding when no profile exists.
  const MeinImpactApp.withProfile({
    required OpportunityRepository opportunityRepository,
    required UserProfileStore profileStore,
    UserProfile? initialProfile,
    super.key,
  })  : _opportunityRepository = opportunityRepository,
        _profileStore = profileStore,
        _initialProfile = initialProfile;

  final OpportunityRepository _opportunityRepository;
  final UserProfileStore? _profileStore;
  final UserProfile? _initialProfile;

  @override
  State<MeinImpactApp> createState() => _MeinImpactAppState();
}

class _MeinImpactAppState extends State<MeinImpactApp> {
  UserProfile? _profile;
  // Onboarding steps (only used before a profile exists): 0 = value
  // profile, 1 = demographics.
  int _onboardingStep = 0;
  Map<String, int>? _pendingWerte;
  // True while an existing profile's owner is re-doing just the Werteprofil
  // quiz from "Mein Profil" — demographic data is left untouched, see
  // _onWerteRequizComplete.
  bool _requizWerte = false;

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
      betroffenheitsprofil:
          patch?.betroffenheitsprofil ?? const Betroffenheitsprofil(),
    );
    await widget._profileStore?.save(profile);
    setState(() => _profile = profile);
  }

  Future<void> _onUseExampleProfile() async {
    const profile = UserProfile(
      betroffenheitsprofil: _kExampleBetroffenheitsprofil,
    );
    await widget._profileStore?.save(profile);
    setState(() => _profile = profile);
  }

  Future<void> _onWerteRequizComplete(Map<String, int> werte) async {
    final current = _profile!;
    final updated = UserProfile(
      werte: werte,
      plz: current.plz,
      mdbName: current.mdbName,
      mdbParty: current.mdbParty,
      mdbWahlkreis: current.mdbWahlkreis,
      betroffenheitsprofil: current.betroffenheitsprofil,
    );
    await widget._profileStore?.save(updated);
    setState(() {
      _profile = updated;
      _requizWerte = false;
    });
  }

  Future<void> _onBetroffenheitsprofilChanged(
    Betroffenheitsprofil betroffenheitsprofil,
  ) async {
    final current = _profile!;
    final updated = UserProfile(
      werte: current.werte,
      plz: current.plz,
      mdbName: current.mdbName,
      mdbParty: current.mdbParty,
      mdbWahlkreis: current.mdbWahlkreis,
      betroffenheitsprofil: betroffenheitsprofil,
    );
    await widget._profileStore?.save(updated);
    setState(() => _profile = updated);
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
      return MainTabScreen(
        opportunityRepository: widget._opportunityRepository,
      );
    }

    // Profile loaded → show the tab shell (unless the owner chose to redo
    // just the Werteprofil quiz — demographic data is always editable
    // inline instead, see onBetroffenheitsprofilChanged below).
    if (_profile != null && !_requizWerte) {
      return MainTabScreen(
        opportunityRepository: widget._opportunityRepository,
        profile: _profile,
        onEditProfile: () => setState(() => _requizWerte = true),
        onBetroffenheitsprofilChanged: _onBetroffenheitsprofilChanged,
      );
    }

    if (_requizWerte) {
      return ValueProfileScreen(onComplete: _onWerteRequizComplete);
    }

    // Onboarding step 0: value profile
    if (_onboardingStep == 0) {
      return ValueProfileScreen(
        onComplete: _onWerteComplete,
        onUseExampleProfile: _onUseExampleProfile,
      );
    }

    // Onboarding step 1: demographics (PLZ + MdB + Betroffenheitsprofil) —
    // optional
    return DemographicScreen(
      onComplete: _onDemographicComplete,
      onLookupMdb: widget._opportunityRepository.lookupMdb,
    );
  }
}
