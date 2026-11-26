import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../core/usage/usage.dart';
import '../features/feed/domain/interest_config.dart';
import '../features/feed/domain/interest_weights.dart';
import '../features/feed/domain/opportunity.dart';
import '../features/feed/domain/opportunity_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/feed/presentation/aktionen_tab.dart';
import '../features/feed/presentation/widgets/profile_column.dart';
import '../features/feedback/feedback_sheets.dart';
import '../features/tracking/domain/action_log.dart';
import '../features/tracking/domain/progress.dart';
import '../features/tracking/wirkung_tab.dart';
import 'theme/mi_theme.dart';

/// App root: three bottom-navigation tabs (Profil, Meine Aktionen, Wirkung — no
/// language switcher, no side-by-side desktop layout; a plain, modern
/// mobile-style tab bar).
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({
    required this.opportunityRepository,
    this.profile,
    this.profileRevision = 0,
    this.initialTab = 1,
    this.openTab,
    this.onEditProfile,
    this.onEditLebenslagen,
    this.onEditPrioritaeten,
    this.onFillIn,
    this.onLebenslagenChanged,
    this.onInterestsChanged,
    this.onInterestSignal,
    this.doneIds = const {},
    this.doneActions = const [],
    this.onActionDone,
    this.dismissedIds = const {},
    this.onCardsDismissed,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.interestConfig = const InterestConfig(),
    super.key,
  });

  final OpportunityRepository opportunityRepository;
  final UserProfile? profile;
  // Bumped by each profile edit made in the shell; the hand re-ranks.
  final int profileRevision;

  /// 0 Mein Profil, 1 Meine Aktionen (the default), 2 Mein Impact.
  final int initialTab;
  // Tabs to switch to from outside, e.g. a tapped notification.
  final Stream<int>? openTab;
  final VoidCallback? onEditProfile;
  // Opens the Rucksack to re-pack PLZ and Lebenslagen; without it the
  // profile edits the Lebenslagen in a sheet.
  final VoidCallback? onEditLebenslagen;
  // Opens the Stadthaushalt to distribute the Taler again.
  final VoidCallback? onEditPrioritaeten;
  // Starts the questionnaire for a profile that put it off.
  final VoidCallback? onFillIn;
  final ValueChanged<Set<String>>? onLebenslagenChanged;
  final ValueChanged<InterestWeights>? onInterestsChanged;
  final void Function(List<String> tags, InterestSignal signal)?
      onInterestSignal;
  final Set<String> doneIds;
  // The action log, oldest first.
  final List<ActionLogEntry> doneActions;
  final void Function(Opportunity opportunity, ActionVia via)? onActionDone;
  // Cards thrown away from the hand.
  final Set<String> dismissedIds;
  final ValueChanged<Set<String>>? onCardsDismissed;
  // Light, dark or the phone's; no choice in the profile without the
  // callback.
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final InterestConfig interestConfig;

  static const _fallbackProfile = UserProfile();

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  // Meine Aktionen unless the shell comes back from a profile edit.
  late int _tabIndex = widget.initialTab;
  // Done actions the user has not looked at in Wirkung yet; the Wirkung tab
  // shows their count where played cards land.
  late int _seenDone = widget.doneActions.length;
  StreamSubscription<int>? _openTab;

  @override
  void initState() {
    super.initState();
    _openTab = widget.openTab?.listen(_select);
  }

  @override
  void dispose() {
    unawaited(_openTab?.cancel());
    super.dispose();
  }

  // The tab a message was written on, for /admin/feedback.
  static const _screens = ['profil', 'aktionen', 'impact'];

  // Beta feedback opens as a sheet over the tab, from the row at the end of
  // the profile.
  Future<void> _giveFeedback(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showFeedbackSheet(context, screen: _screens[_tabIndex]);
    if (!sent) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Danke! Ist angekommen.')));
  }

  void _select(int index) => setState(() {
        if (index == 2 && _tabIndex != 2) {
          Usage.current.count(UsageEvent.impactOpened);
        }
        _tabIndex = index;
        if (index == 2) _seenDone = widget.doneActions.length;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final effectiveProfile = widget.profile ?? MainTabScreen._fallbackProfile;
    final unseen = widget.doneActions.length - _seenDone;
    final progress = Progress.of(ActionLog(widget.doneActions), DateTime.now());

    final tabs = [
      _ProfileTab(
        profile: effectiveProfile,
        progress: progress,
        onEdit: widget.onEditProfile,
        onEditLebenslagen: widget.onEditLebenslagen,
        onEditPrioritaeten: widget.onEditPrioritaeten,
        onFillIn: widget.onFillIn,
        onLebenslagenChanged: widget.onLebenslagenChanged,
        onInterestsChanged: widget.onInterestsChanged,
        onFeedback: _giveFeedback,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
      AktionenTab(
        opportunityRepository: widget.opportunityRepository,
        profile: effectiveProfile,
        profileRevision: widget.profileRevision,
        onInterestSignal: widget.onInterestSignal,
        doneIds: widget.doneIds,
        streak: progress.streak,
        onActionDone: widget.onActionDone,
        dismissedIds: widget.dismissedIds,
        onDismissed: widget.onCardsDismissed,
        interestConfig: widget.interestConfig,
      ),
      // Scrolls itself, for pull-to-refresh.
      WirkungTab(
        opportunityRepository: widget.opportunityRepository,
        doneActions: widget.doneActions,
      ),
    ];

    // The card table is light or dark as the app is (the phone's setting
    // unless chosen in the profile), and so are the status bar icons above
    // it. Outside the app, e.g. in tests, it follows the phone.
    final current = Theme.of(context);
    final theme = current.extension<MiColors>() != null
        ? current
        : miTheme(MediaQuery.platformBrightnessOf(context));
    final brightness = theme.brightness;
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: context.mi.table,
            body: SafeArea(
              child: IndexedStack(index: _tabIndex, children: tabs),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: _select,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: l10n.tabProfile,
                ),
                NavigationDestination(
                  // Turned so the cards fan up and to the right, like the
                  // hand.
                  icon: const RotatedBox(
                    quarterTurns: 2,
                    child: Icon(Icons.style_outlined),
                  ),
                  selectedIcon: const RotatedBox(
                    quarterTurns: 2,
                    child: Icon(Icons.style),
                  ),
                  label: l10n.tabActions,
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: unseen > 0,
                    label: Text('$unseen'),
                    child: const Icon(Icons.timeline_outlined),
                  ),
                  selectedIcon: const Icon(Icons.timeline),
                  label: l10n.tabImpact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.profile,
    required this.progress,
    required this.onEdit,
    required this.onEditLebenslagen,
    required this.onEditPrioritaeten,
    required this.onFillIn,
    required this.onLebenslagenChanged,
    required this.onInterestsChanged,
    required this.onFeedback,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final UserProfile profile;
  final Progress progress;
  final VoidCallback? onEdit;
  final VoidCallback? onEditLebenslagen;
  final VoidCallback? onEditPrioritaeten;
  final VoidCallback? onFillIn;
  final ValueChanged<Set<String>>? onLebenslagenChanged;
  final ValueChanged<InterestWeights>? onInterestsChanged;
  final void Function(BuildContext context) onFeedback;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: MiSpace.lg, bottom: MiSpace.xl),
      child: ProfileColumn(
        profile: profile,
        progress: progress,
        onEdit: onEdit ?? () {},
        onEditLebenslagen: onEditLebenslagen,
        onEditPrioritaeten: onEditPrioritaeten,
        onFillIn: onFillIn,
        onLebenslagenChanged: onLebenslagenChanged ?? (_) {},
        onInterestsChanged: onInterestsChanged ?? (_) {},
        onFeedback: () => onFeedback(context),
        themeMode: themeMode,
        onThemeModeChanged: onThemeModeChanged,
      ),
    );
  }
}
