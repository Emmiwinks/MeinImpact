import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../features/feed/domain/interest_config.dart';
import '../features/feed/domain/interest_weights.dart';
import '../features/feed/domain/opportunity.dart';
import '../features/feed/domain/opportunity_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/feed/presentation/aktionen_tab.dart';
import '../features/feed/presentation/widgets/profile_column.dart';
import '../features/tracking/domain/action_log.dart';
import '../features/tracking/wirkung_tab.dart';
import 'theme/mi_theme.dart';

/// App root: three bottom-navigation tabs (Profil, Meine Aktionen, Wirkung — no
/// language switcher, no side-by-side desktop layout; a plain, modern
/// mobile-style tab bar).
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({
    required this.opportunityRepository,
    this.profile,
    this.onEditProfile,
    this.onLebenslagenChanged,
    this.onInterestsChanged,
    this.onInterestSignal,
    this.doneIds = const {},
    this.doneActions = const [],
    this.onActionDone,
    this.interestConfig = const InterestConfig(),
    super.key,
  });

  final OpportunityRepository opportunityRepository;
  final UserProfile? profile;
  final VoidCallback? onEditProfile;
  final ValueChanged<Set<String>>? onLebenslagenChanged;
  final ValueChanged<InterestWeights>? onInterestsChanged;
  final void Function(Opportunity opportunity, InterestSignal signal)?
      onInterestSignal;
  final Set<String> doneIds;
  // The action log, oldest first.
  final List<ActionLogEntry> doneActions;
  final void Function(Opportunity opportunity, ActionVia via)? onActionDone;
  final InterestConfig interestConfig;

  static const _fallbackProfile = UserProfile();

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _tabIndex =
      1; // default to Meine Aktionen — the primary "what now" screen
  // Done actions the user has not looked at in Wirkung yet; the Wirkung tab
  // shows their count where played cards land.
  late int _seenDone = widget.doneActions.length;

  void _select(int index) => setState(() {
        _tabIndex = index;
        if (index == 2) _seenDone = widget.doneActions.length;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final effectiveProfile = widget.profile ?? MainTabScreen._fallbackProfile;
    final unseen = widget.doneActions.length - _seenDone;

    final tabs = [
      _ProfileTab(
        profile: effectiveProfile,
        onEdit: widget.onEditProfile,
        onLebenslagenChanged: widget.onLebenslagenChanged,
        onInterestsChanged: widget.onInterestsChanged,
      ),
      AktionenTab(
        opportunityRepository: widget.opportunityRepository,
        profile: effectiveProfile,
        onInterestSignal: widget.onInterestSignal,
        doneIds: widget.doneIds,
        onActionDone: widget.onActionDone,
        interestConfig: widget.interestConfig,
      ),
      // Scrolls itself, for pull-to-refresh.
      WirkungTab(
        opportunityRepository: widget.opportunityRepository,
        doneActions: widget.doneActions,
      ),
    ];

    // The card table follows the phone's light or dark setting, and so do
    // the status bar icons above it.
    final brightness = MediaQuery.platformBrightnessOf(context);
    return Theme(
      data: miTheme(brightness),
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
                  icon: const Icon(Icons.style_outlined),
                  selectedIcon: const Icon(Icons.style),
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
    required this.onEdit,
    required this.onLebenslagenChanged,
    required this.onInterestsChanged,
  });

  final UserProfile profile;
  final VoidCallback? onEdit;
  final ValueChanged<Set<String>>? onLebenslagenChanged;
  final ValueChanged<InterestWeights>? onInterestsChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: MiSpace.lg, bottom: MiSpace.xl),
      child: ProfileColumn(
        profile: profile,
        onEdit: onEdit ?? () {},
        onLebenslagenChanged: onLebenslagenChanged ?? (_) {},
        onInterestsChanged: onInterestsChanged ?? (_) {},
      ),
    );
  }
}
