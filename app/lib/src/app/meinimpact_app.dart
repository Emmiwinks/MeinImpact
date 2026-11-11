import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../core/profile/user_profile_store.dart';
import '../features/feed/domain/interest_config.dart';
import '../features/feed/domain/interest_weights.dart';
import '../features/feed/domain/opportunity.dart';
import '../features/feed/domain/opportunity_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/onboarding/demographic_screen.dart';
import '../features/onboarding/value_profile_screen.dart';
import '../features/tracking/data/action_log_store.dart';
import '../features/tracking/domain/action_log.dart';
import 'main_tab_screen.dart';

/// Hardcoded stand-in Lebenslagen, used by the "Beispiel-Profil übernehmen"
/// onboarding shortcut. Deliberately not configurable: it exists to skip
/// setup, not to represent a real answer.
const _kExampleLebenslagen = {'mieter', 'oepnv', 'angestellt'};

class MeinImpactApp extends StatefulWidget {
  /// Direct constructor — bypasses onboarding (used in tests and demos).
  const MeinImpactApp({
    required OpportunityRepository opportunityRepository,
    InterestConfig interestConfig = const InterestConfig(),
    super.key,
  })  : _opportunityRepository = opportunityRepository,
        _interestConfig = interestConfig,
        _profileStore = null,
        _initialProfile = null,
        _actionLogStore = null,
        _initialActionLog = const ActionLog();

  /// Production constructor — shows onboarding when no profile exists.
  const MeinImpactApp.withProfile({
    required OpportunityRepository opportunityRepository,
    required UserProfileStore profileStore,
    required ActionLogStore actionLogStore,
    UserProfile? initialProfile,
    ActionLog initialActionLog = const ActionLog(),
    InterestConfig interestConfig = const InterestConfig(),
    super.key,
  })  : _opportunityRepository = opportunityRepository,
        _interestConfig = interestConfig,
        _profileStore = profileStore,
        _initialProfile = initialProfile,
        _actionLogStore = actionLogStore,
        _initialActionLog = initialActionLog;

  final OpportunityRepository _opportunityRepository;
  final InterestConfig _interestConfig;
  final UserProfileStore? _profileStore;
  final UserProfile? _initialProfile;
  final ActionLogStore? _actionLogStore;
  final ActionLog _initialActionLog;

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
  late ActionLog _actionLog;

  @override
  void initState() {
    super.initState();
    _profile = widget._initialProfile;
    _actionLog = widget._initialActionLog;
  }

  Future<void> _onActionDone(Opportunity opportunity, ActionVia via) async {
    if (_actionLog.isDone(opportunity.id)) return;
    final updated = _actionLog.withDone(
      ActionLogEntry.fromOpportunity(
        opportunity,
        doneAt: DateTime.now(),
        via: via,
      ),
    );
    setState(() => _actionLog = updated);
    // Best effort: offline, the mark is lost and Mein Impact just doesn't
    // follow this one. Never blocks or fails the user's "Fertig".
    unawaited(
      widget._opportunityRepository
          .markTracked(opportunity.id)
          .catchError((Object _) {}),
    );
    await widget._actionLogStore?.save(updated);
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
      lebenslagen: patch?.lebenslagen ?? const {},
    );
    await widget._profileStore?.save(profile);
    setState(() => _profile = profile);
  }

  Future<void> _onUseExampleProfile() async {
    const profile = UserProfile(lebenslagen: _kExampleLebenslagen);
    await widget._profileStore?.save(profile);
    setState(() => _profile = profile);
  }

  Future<void> _onWerteRequizComplete(Map<String, int> werte) async {
    final updated = _profile!.copyWith(werte: werte);
    await widget._profileStore?.save(updated);
    setState(() {
      _profile = updated;
      _requizWerte = false;
    });
  }

  Future<void> _onLebenslagenChanged(Set<String> lebenslagen) async {
    final updated = _profile!.copyWith(lebenslagen: lebenslagen);
    await widget._profileStore?.save(updated);
    setState(() => _profile = updated);
  }

  Future<void> _onInterestsChanged(InterestWeights interests) async {
    final updated = _profile!.copyWith(interests: interests);
    await widget._profileStore?.save(updated);
    setState(() => _profile = updated);
  }

  // Interests are learned silently: persisted, but the open feed is not
  // re-ranked under the user's finger (the next feed load picks them up).
  Future<void> _onInterestSignal(
    Opportunity opportunity,
    InterestSignal signal,
  ) async {
    final current = _profile;
    if (current == null) return;
    final updated = current.copyWith(
      interests: current.interests.record(
        opportunity.affectedTags,
        signal,
        DateTime.now(),
        widget._interestConfig,
      ),
    );
    _profile = updated;
    await widget._profileStore?.save(updated);
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
        doneIds: _actionLog.doneIds,
        onActionDone: _onActionDone,
      );
    }

    // Profile loaded → show the tab shell (unless the owner chose to redo
    // just the Werteprofil quiz — demographic data is always editable
    // inline instead, see onLebenslagenChanged below).
    if (_profile != null && !_requizWerte) {
      return MainTabScreen(
        opportunityRepository: widget._opportunityRepository,
        profile: _profile,
        onEditProfile: () => setState(() => _requizWerte = true),
        onLebenslagenChanged: _onLebenslagenChanged,
        onInterestsChanged: _onInterestsChanged,
        onInterestSignal: _onInterestSignal,
        doneIds: _actionLog.doneIds,
        onActionDone: _onActionDone,
        interestConfig: widget._interestConfig,
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

    // Onboarding step 1: demographics (PLZ + MdB + Lebenslagen) —
    // optional
    return DemographicScreen(
      onComplete: _onDemographicComplete,
      onLookupMdb: widget._opportunityRepository.lookupMdb,
    );
  }
}
