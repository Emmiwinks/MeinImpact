import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../core/profile/user_profile_store.dart';
import '../core/usage/usage.dart';
import '../features/feed/data/dismissed_cards_store.dart';
import '../features/feed/domain/home_location.dart';
import '../features/feed/domain/interest_config.dart';
import '../features/feed/domain/interest_weights.dart';
import '../features/feed/domain/opportunity.dart';
import '../features/feed/domain/opportunity_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/notifications/domain/notification_state.dart';
import '../features/notifications/notification_widgets.dart';
import '../features/notifications/notifications.dart';
import '../features/onboarding/consent_screen.dart';
import '../features/onboarding/intro_screen.dart';
import '../features/onboarding/rucksack/rucksack_screen.dart';
import '../features/onboarding/stadthaushalt/stadthaushalt_screen.dart';
import '../features/onboarding/value_profile_screen.dart';
import '../features/tracking/data/action_log_store.dart';
import '../features/tracking/domain/action_log.dart';
import '../features/tracking/domain/progress.dart';
import '../features/tracking/progress_widgets.dart';
import 'main_tab_screen.dart';
import 'theme/mi_theme.dart';

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
        _initialActionLog = const ActionLog(),
        _dismissedStore = null,
        _initialDismissed = const {};

  /// Production constructor — shows onboarding when no profile exists.
  const MeinImpactApp.withProfile({
    required OpportunityRepository opportunityRepository,
    required UserProfileStore profileStore,
    required ActionLogStore actionLogStore,
    DismissedCardsStore? dismissedStore,
    UserProfile? initialProfile,
    ActionLog initialActionLog = const ActionLog(),
    Set<String> initialDismissed = const {},
    InterestConfig interestConfig = const InterestConfig(),
    super.key,
  })  : _opportunityRepository = opportunityRepository,
        _interestConfig = interestConfig,
        _profileStore = profileStore,
        _initialProfile = initialProfile,
        _actionLogStore = actionLogStore,
        _initialActionLog = initialActionLog,
        _dismissedStore = dismissedStore,
        _initialDismissed = initialDismissed;

  final OpportunityRepository _opportunityRepository;
  final InterestConfig _interestConfig;
  final UserProfileStore? _profileStore;
  final UserProfile? _initialProfile;
  final ActionLogStore? _actionLogStore;
  final ActionLog _initialActionLog;
  final DismissedCardsStore? _dismissedStore;
  final Set<String> _initialDismissed;

  @override
  State<MeinImpactApp> createState() => _MeinImpactAppState();
}

class _MeinImpactAppState extends State<MeinImpactApp>
    with WidgetsBindingObserver {
  UserProfile? _profile;
  // Onboarding steps (only used before a profile exists), see _Step.
  _Step _onboardingStep = _Step.intro;
  // The consent was reached through "Lieber später".
  bool _later = false;
  // True while someone who put the questionnaire off fills it in from
  // "Mein Profil": the onboarding steps run again, the consent is had.
  bool _fillIn = false;
  DateTime? _consentAt;
  Map<String, double>? _pendingWerte;
  // PLZ and Lebenslagen from the Rucksack, kept for the Stadthaushalt step
  // and for going back to the Rucksack.
  UserProfile? _pendingRucksack;
  // True while the owner re-distributes the Stadthaushalt from "Mein
  // Profil".
  bool _redistribute = false;
  // True while an existing profile's owner is re-doing just the Werteprofil
  // quiz from "Mein Profil" — demographic data is left untouched, see
  // _onWerteRequizComplete.
  bool _requizWerte = false;
  // True while the owner re-packs the Rucksack (PLZ and Lebenslagen) from
  // "Mein Profil".
  bool _repack = false;
  // The tab the shell opens on: back from those two, it is Mein Profil.
  int _homeTab = 1;
  // Counts the profile edits made inside the tab shell (Lebenslagen,
  // interests); the hand re-ranks on each. Learned signals don't count.
  int _profileRevision = 0;
  late ActionLog _actionLog;
  // Cards thrown away from the hand.
  late Set<String> _dismissed;
  final _navigatorKey = GlobalKey<NavigatorState>();
  // Tabs a notification asks to open.
  final _openTab = StreamController<int>.broadcast();

  @override
  void initState() {
    super.initState();
    _profile = widget._initialProfile;
    _actionLog = widget._initialActionLog;
    _dismissed = widget._initialDismissed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(Usage.current.markActive());
    unawaited(_locateHomeIfMissing());
    Notifications.current.taps.addListener(_onNotificationTap);
    // A tap that started the app, once the tabs are there to open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNotificationTap());
  }

  Future<void> _onNotificationTap() async {
    final tap = Notifications.current.taps.value;
    if (tap == null || _profile == null) return;
    Notifications.current.taps.value = null;
    final id = tap.opportunityId;
    final tookPart = tap.action == kTookPartAction;
    if (tookPart && id != null) {
      final card = await Notifications.current.lookedAtCard(id);
      if (card != null) await _logDone(card.withDoneAt(DateTime.now()));
    }
    // What became of actions is in Mein Impact, the rest in Meine Aktionen.
    final aboutImpact = tookPart ||
        tap.kind == NotificationKind.result ||
        tap.kind == NotificationKind.decision ||
        tap.kind == NotificationKind.news;
    _openTab.add(aboutImpact ? 2 : 1);
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
      prioritaeten: latest.prioritaeten,
      einwilligung: latest.einwilligung,
    );
    await widget._profileStore?.save(updated);
    if (mounted) setState(() => _profile = updated);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Notifications.current.taps.removeListener(_onNotificationTap);
    unawaited(_openTab.close());
    super.dispose();
  }

  // Phones keep the app alive for days, so coming back counts as use too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(Usage.current.markActive());
      unawaited(Notifications.current.opened());
    }
  }

  Future<void> _onActionDone(Opportunity opportunity, ActionVia via) =>
      _logDone(
        ActionLogEntry.fromOpportunity(
          opportunity,
          doneAt: DateTime.now(),
          via: via,
        ),
      );

  Future<void> _logDone(ActionLogEntry entry) async {
    if (_actionLog.isDone(entry.opportunityId)) return;
    Usage.current.count(UsageEvent.actionDone);
    final now = DateTime.now();
    final first = _actionLog.entries.isEmpty;
    final updated = _actionLog.withDone(entry);
    final moment = ProgressMoment.between(
      Progress.of(_actionLog, now),
      Progress.of(updated, now),
    );
    setState(() => _actionLog = updated);
    // The card has landed on the Wirkung pile by now. After the first
    // action, once its badges are shown, the app asks about notifications.
    final navigator = _navigatorKey.currentContext;
    if (navigator != null && (moment != null || first)) {
      unawaited(() async {
        if (moment != null) await showProgressMoment(navigator, moment);
        if (first && navigator.mounted) await askForNotifications(navigator);
      }());
    }
    // Best effort: offline, the mark is lost and Mein Impact just doesn't
    // follow this one. Never blocks or fails the user's "Fertig".
    unawaited(
      widget._opportunityRepository
          .markTracked(entry.opportunityId)
          .catchError((Object _) {}),
    );
    await widget._actionLogStore?.save(updated);
    // The flame may be safe now, and reminders about it are done.
    Notifications.current.refresh();
  }

  Future<void> _onCardsDismissed(Set<String> ids) async {
    final updated = {..._dismissed, ...ids};
    setState(() => _dismissed = updated);
    await widget._dismissedStore?.save(updated);
  }

  Future<void> _onConsent() async {
    final now = DateTime.now();
    final existing = _profile;
    // A profile from before the consent screen agrees once, on start.
    if (existing != null) {
      final updated = existing.copyWith(einwilligung: now);
      await widget._profileStore?.save(updated);
      setState(() => _profile = updated);
      return;
    }
    // Onboarding counts as done once the questionnaire is.
    if (_later) {
      final profile = UserProfile.browsing(einwilligung: now);
      await widget._profileStore?.save(profile);
      setState(() => _profile = profile);
      return;
    }
    setState(() {
      _consentAt = now;
      _onboardingStep = _Step.werte;
    });
  }

  Future<void> _onWerteComplete(Map<String, double> werte) async {
    setState(() {
      _pendingWerte = werte;
      _onboardingStep = _Step.rucksack;
    });
  }

  void _onRucksackComplete(UserProfile patch) {
    setState(() {
      _pendingRucksack = patch;
      _onboardingStep = _Step.stadthaushalt;
    });
  }

  // From "Mein Profil": the questionnaire, after only looking so far.
  void _startFillIn() => setState(() {
        _fillIn = true;
        _consentAt = _profile?.einwilligung;
        _pendingWerte = null;
        _pendingRucksack = null;
        _onboardingStep = _Step.werte;
      });

  Future<void> _onStadthaushaltComplete(Map<String, int> taler) async {
    final patch = _pendingRucksack!;
    // What the cards taught while only looking is kept.
    final learned = _profile?.interests ?? const InterestWeights();
    final profile = UserProfile(
      werte: _pendingWerte!,
      plz: patch.plz,
      mdbName: patch.mdbName,
      mdbParty: patch.mdbParty,
      mdbWahlkreis: patch.mdbWahlkreis,
      home: patch.home,
      lebenslagen: patch.lebenslagen,
      interests: learned,
      prioritaeten: taler,
      einwilligung: _consentAt,
    );
    Usage.current.count(UsageEvent.onboardingDone);
    await widget._profileStore?.save(profile);
    setState(() {
      _profile = profile;
      _fillIn = false;
      _homeTab = 1;
      _profileRevision++;
    });
    unawaited(_locateHomeIfMissing());
  }

  // "Neu verteilen" from the profile, or the first distribution for a
  // profile made before the step existed.
  Future<void> _onRedistributeComplete(Map<String, int> taler) async {
    final updated = _profile!.copyWith(prioritaeten: taler);
    await widget._profileStore?.save(updated);
    setState(() {
      _profile = updated;
      if (_redistribute) _homeTab = 0;
      _redistribute = false;
    });
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
      prioritaeten: current.prioritaeten,
      einwilligung: current.einwilligung,
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
    setState(() {
      _profile = updated;
      _profileRevision++;
    });
  }

  Future<void> _onInterestsChanged(InterestWeights interests) async {
    final updated = _profile!.copyWith(interests: interests);
    await widget._profileStore?.save(updated);
    setState(() {
      _profile = updated;
      _profileRevision++;
    });
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
        dismissedIds: _dismissed,
        onCardsDismissed: _onCardsDismissed,
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

    // Profiles from before the consent screen and the Stadthaushalt step
    // catch up on them once, before the tabs.
    if (_profile != null && _profile!.einwilligung == null) {
      return ConsentScreen(onAgree: _onConsent);
    }
    if (_profile != null &&
        !_fillIn &&
        (_redistribute ||
            (_profile!.prioritaeten.isEmpty && !_profile!.browsing))) {
      return StadthaushaltScreen(
        initial: _profile!.prioritaeten,
        onComplete: _onRedistributeComplete,
        onBack: _redistribute
            ? () => setState(() {
                  _redistribute = false;
                  _homeTab = 0;
                })
            : null,
      );
    }

    if (_profile != null && !_requizWerte && !_fillIn) {
      return MainTabScreen(
        opportunityRepository: widget._opportunityRepository,
        profile: _profile,
        profileRevision: _profileRevision,
        initialTab: _homeTab,
        openTab: _openTab.stream,
        onEditProfile: () => setState(() => _requizWerte = true),
        onEditLebenslagen: () => setState(() => _repack = true),
        onEditPrioritaeten: () => setState(() => _redistribute = true),
        onFillIn: _startFillIn,
        onLebenslagenChanged: _onLebenslagenChanged,
        onInterestsChanged: _onInterestsChanged,
        onInterestSignal: _onInterestSignal,
        doneIds: _actionLog.doneIds,
        doneActions: _actionLog.entries,
        onActionDone: _onActionDone,
        dismissedIds: _dismissed,
        onCardsDismissed: _onCardsDismissed,
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

    // Onboarding: what is asked, the consent, then the three parts. Back
    // steps through them, keeping what was entered.
    switch (_onboardingStep) {
      case _Step.intro:
        return IntroScreen(
          onStart: () => setState(() {
            _later = false;
            _onboardingStep = _Step.consent;
          }),
          onLater: () => setState(() {
            _later = true;
            _onboardingStep = _Step.consent;
          }),
        );
      case _Step.consent:
        return ConsentScreen(
          onAgree: _onConsent,
          onBack: () => setState(() => _onboardingStep = _Step.intro),
        );
      case _Step.werte:
        return ValueProfileScreen(
          initial: _pendingWerte ?? const {},
          onComplete: _onWerteComplete,
          // Filling in from the profile, back leads there again.
          onCancel: () => setState(() {
            if (_fillIn) {
              _fillIn = false;
              _homeTab = 0;
            } else {
              _onboardingStep = _Step.consent;
            }
          }),
        );
      case _Step.rucksack:
        final back = _pendingRucksack;
        return RucksackScreen(
          werte: _pendingWerte ?? const {},
          // The picture falls in only the first time.
          dropPicture: back == null,
          initialPlz: back?.plz,
          initialWahlkreis: back?.mdbWahlkreis,
          initialLebenslagen: back?.lebenslagen ?? const {},
          onComplete: _onRucksackComplete,
          onLocate: widget._opportunityRepository.locate,
          onBack: () => setState(() => _onboardingStep = _Step.werte),
        );
      case _Step.stadthaushalt:
        return StadthaushaltScreen(
          onComplete: _onStadthaushaltComplete,
          onBack: () => setState(() => _onboardingStep = _Step.rucksack),
        );
    }
  }
}

enum _Step { intro, consent, werte, rucksack, stadthaushalt }
