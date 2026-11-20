import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../core/profile/user_profile_store.dart';
import '../core/usage/usage.dart';
import '../features/feed/domain/home_location.dart';
import '../features/feed/domain/interest_config.dart';
import '../features/feed/domain/interest_weights.dart';
import '../features/feed/domain/opportunity.dart';
import '../features/feed/domain/opportunity_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/onboarding/rucksack/rucksack_screen.dart';
import '../features/onboarding/value_profile_screen.dart';
import '../features/tracking/data/action_log_store.dart';
import '../features/tracking/domain/action_log.dart';
import '../features/tracking/domain/progress.dart';
import '../features/tracking/progress_widgets.dart';
import 'main_tab_screen.dart';
import 'theme/mi_theme.dart';

/// Hardcoded stand-in Lebenslagen, used by the "Beispiel-Profil übernehmen"
/// onboarding shortcut. Deliberately not configurable: it exists to skip
/// setup, not to represent a real answer.
const _kExampleLebenslagen = {'mieter', 'oepnv', 'angestellt'};
// Its PLZ is located like any other once the app is running.
const _kExamplePlz = '01067';

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

class _MeinImpactAppState extends State<MeinImpactApp>
    with WidgetsBindingObserver {
  UserProfile? _profile;
  // Onboarding steps (only used before a profile exists): 0 = value
  // profile, 1 = demographics.
  int _onboardingStep = 0;
  Map<String, double>? _pendingWerte;
  // True while an existing profile's owner is re-doing just the Werteprofil
  // quiz from "Mein Profil" — demographic data is left untouched, see
  // _onWerteRequizComplete.
  bool _requizWerte = false;
  // True while the owner re-packs the Rucksack (PLZ and Lebenslagen) from
  // "Mein Profil".
  bool _repack = false;
  // The tab the shell opens on: back from those two, it is Mein Profil.
  int _homeTab = 1;
  late ActionLog _actionLog;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _profile = widget._initialProfile;
    _actionLog = widget._initialActionLog;
    WidgetsBinding.instance.addObserver(this);
    unawaited(Usage.current.markActive());
    unawaited(_locateHomeIfMissing());
  }

  // A PLZ entered offline, or saved before the app kept where it lies, is
  // located on the next start: quietly, best effort, the next feed load
  // uses it.
  Future<void> _locateHomeIfMissing() async {
    final current = _profile;
    final plz = current?.plz;
    if (current == null || plz == null || current.home != null) return;
    final PlzLookup? found;
    try {
      found = await widget._opportunityRepository.locate(plz);
    } catch (_) {
      return;
    }
    if (found == null || !mounted || _profile?.plz != plz) return;
    final latest = _profile!;
    // A member of the Bundestag only when the PLZ has just one.
    final mdb = latest.mdbWahlkreis == null && found.wahlkreise.length == 1
        ? found.wahlkreise.single
        : null;
    final updated = UserProfile(
      werte: latest.werte,
      region: latest.region,
      plz: latest.plz,
      mdbName: mdb?.mdbName ?? latest.mdbName,
      mdbParty: mdb?.mdbParty ?? latest.mdbParty,
      mdbWahlkreis: mdb?.wahlkreisName ?? latest.mdbWahlkreis,
      home: found.home,
      lebenslagen: latest.lebenslagen,
      interests: latest.interests,
    );
    await widget._profileStore?.save(updated);
    if (mounted) setState(() => _profile = updated);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Phones keep the app alive for days, so coming back counts as use too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(Usage.current.markActive());
    }
  }

  Future<void> _onActionDone(Opportunity opportunity, ActionVia via) async {
    if (_actionLog.isDone(opportunity.id)) return;
    Usage.current.count(UsageEvent.actionDone);
    final now = DateTime.now();
    final updated = _actionLog.withDone(
      ActionLogEntry.fromOpportunity(opportunity, doneAt: now, via: via),
    );
    final moment = ProgressMoment.between(
      Progress.of(_actionLog, now),
      Progress.of(updated, now),
    );
    setState(() => _actionLog = updated);
    // The card has landed on the Wirkung pile by now.
    final navigator = _navigatorKey.currentContext;
    if (moment != null && navigator != null) {
      unawaited(showProgressMoment(navigator, moment));
    }
    // Best effort: offline, the mark is lost and Mein Impact just doesn't
    // follow this one. Never blocks or fails the user's "Fertig".
    unawaited(
      widget._opportunityRepository
          .markTracked(opportunity.id)
          .catchError((Object _) {}),
    );
    await widget._actionLogStore?.save(updated);
  }

  Future<void> _onWerteComplete(Map<String, double> werte) async {
    setState(() {
      _pendingWerte = werte;
      _onboardingStep = 1;
    });
  }

  Future<void> _onDemographicComplete(UserProfile patch) async {
    final profile = UserProfile(
      werte: _pendingWerte!,
      plz: patch.plz,
      mdbName: patch.mdbName,
      mdbParty: patch.mdbParty,
      mdbWahlkreis: patch.mdbWahlkreis,
      home: patch.home,
      lebenslagen: patch.lebenslagen,
    );
    Usage.current.count(UsageEvent.onboardingDone);
    await widget._profileStore?.save(profile);
    setState(() => _profile = profile);
    unawaited(_locateHomeIfMissing());
  }

  Future<void> _onUseExampleProfile() async {
    const profile = UserProfile(
      plz: _kExamplePlz,
      lebenslagen: _kExampleLebenslagen,
    );
    Usage.current.count(UsageEvent.onboardingDone);
    await widget._profileStore?.save(profile);
    setState(() => _profile = profile);
    unawaited(_locateHomeIfMissing());
  }

  Future<void> _onWerteRequizComplete(Map<String, double> werte) async {
    final updated = _profile!.copyWith(werte: werte);
    await widget._profileStore?.save(updated);
    setState(() {
      _profile = updated;
      _requizWerte = false;
      _homeTab = 0;
    });
  }

  Future<void> _onRepackComplete(UserProfile patch) async {
    final current = _profile!;
    final samePlz = patch.plz != null && patch.plz == current.plz;
    final keepMdb = samePlz && patch.mdbWahlkreis == null;
    final updated = UserProfile(
      werte: current.werte,
      region: current.region,
      plz: patch.plz,
      // The same PLZ without a fresh lookup (offline) keeps its members
      // and where it lies.
      mdbName: keepMdb ? current.mdbName : patch.mdbName,
      mdbParty: keepMdb ? current.mdbParty : patch.mdbParty,
      mdbWahlkreis: keepMdb ? current.mdbWahlkreis : patch.mdbWahlkreis,
      home: patch.home ?? (samePlz ? current.home : null),
      lebenslagen: patch.lebenslagen,
      interests: current.interests,
    );
    await widget._profileStore?.save(updated);
    setState(() {
      _profile = updated;
      _repack = false;
      _homeTab = 0;
    });
    unawaited(_locateHomeIfMissing());
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
    List<String> tags,
    InterestSignal signal,
  ) async {
    final current = _profile;
    if (current == null) return;
    final updated = current.copyWith(
      interests: current.interests.record(
        tags,
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
      navigatorKey: _navigatorKey,
      // No language switcher — German only, matching the real user base.
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      // Every screen lies on the card table, light or dark with the phone.
      theme: miTheme(Brightness.light),
      darkTheme: miTheme(Brightness.dark),
      // Status bar icons follow the table; app bars set their own.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: child!,
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
        doneActions: _actionLog.entries,
        onActionDone: _onActionDone,
      );
    }

    // Profile loaded → show the tab shell (unless the owner chose to redo
    // just the Werteprofil quiz — demographic data is always editable
    // inline instead, see onLebenslagenChanged below).
    if (_profile != null && _repack) {
      return RucksackScreen(
        werte: _profile!.werte,
        dropPicture: false,
        initialPlz: _profile!.plz,
        initialWahlkreis: _profile!.mdbWahlkreis,
        initialLebenslagen: _profile!.lebenslagen,
        onComplete: _onRepackComplete,
        onLocate: widget._opportunityRepository.locate,
        onBack: () => setState(() {
          _repack = false;
          _homeTab = 0;
        }),
      );
    }

    if (_profile != null && !_requizWerte) {
      return MainTabScreen(
        opportunityRepository: widget._opportunityRepository,
        profile: _profile,
        initialTab: _homeTab,
        onEditProfile: () => setState(() => _requizWerte = true),
        onEditLebenslagen: () => setState(() => _repack = true),
        onLebenslagenChanged: _onLebenslagenChanged,
        onInterestsChanged: _onInterestsChanged,
        onInterestSignal: _onInterestSignal,
        doneIds: _actionLog.doneIds,
        doneActions: _actionLog.entries,
        onActionDone: _onActionDone,
        interestConfig: widget._interestConfig,
      );
    }

    if (_requizWerte) {
      return ValueProfileScreen(
        initial: _profile!.werte,
        onComplete: _onWerteRequizComplete,
        onCancel: () => setState(() {
          _requizWerte = false;
          _homeTab = 0;
        }),
      );
    }

    // Onboarding step 0: value profile
    if (_onboardingStep == 0) {
      return ValueProfileScreen(
        // Back from the Rucksack keeps what was answered.
        initial: _pendingWerte ?? const {},
        onComplete: _onWerteComplete,
        onUseExampleProfile: _onUseExampleProfile,
      );
    }

    // Onboarding step 1: the Rucksack (PLZ + MdB, then Lebenslagen) —
    // optional
    return RucksackScreen(
      werte: _pendingWerte ?? const {},
      onComplete: _onDemographicComplete,
      onLocate: widget._opportunityRepository.locate,
      onBack: () => setState(() => _onboardingStep = 0),
    );
  }
}
