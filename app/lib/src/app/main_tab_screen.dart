import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../features/feed/domain/interest_config.dart';
import '../features/feed/domain/interest_weights.dart';
import '../features/feed/domain/opportunity.dart';
import '../features/feed/domain/opportunity_repository.dart';
import '../features/feed/domain/user_profile.dart';
import '../features/feed/presentation/aktionen_tab.dart';
import '../features/feed/presentation/widgets/app_colors.dart';
import '../features/feed/presentation/widgets/profile_column.dart';
import '../features/tracking/wirkung_tab.dart';

/// App root: three bottom-navigation tabs (Profil, Aktionen, Wirkung — no
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
  final InterestConfig interestConfig;

  static const _fallbackProfile = UserProfile();

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _tabIndex = 1; // default to Aktionen — the primary "what now" screen

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final effectiveProfile = widget.profile ?? MainTabScreen._fallbackProfile;

    final tabs = [
      _ProfileTab(
        profile: effectiveProfile,
        onEdit: widget.onEditProfile,
        onLebenslagenChanged: widget.onLebenslagenChanged,
        onInterestsChanged: widget.onInterestsChanged,
      ),
      _AktionenScaffoldTab(
        opportunityRepository: widget.opportunityRepository,
        profile: effectiveProfile,
        onInterestSignal: widget.onInterestSignal,
        interestConfig: widget.interestConfig,
      ),
      const _WirkungScaffoldTab(),
    ];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: IndexedStack(index: _tabIndex, children: tabs),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.tabProfile,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bolt_outlined),
            selectedIcon: const Icon(Icons.bolt),
            label: l10n.tabActions,
          ),
          NavigationDestination(
            icon: const Icon(Icons.timeline_outlined),
            selectedIcon: const Icon(Icons.timeline),
            label: l10n.tabImpact,
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
      child: ProfileColumn(
        profile: profile,
        onEdit: onEdit ?? () {},
        onLebenslagenChanged: onLebenslagenChanged ?? (_) {},
        onInterestsChanged: onInterestsChanged ?? (_) {},
      ),
    );
  }
}

class _AktionenScaffoldTab extends StatelessWidget {
  const _AktionenScaffoldTab({
    required this.opportunityRepository,
    required this.profile,
    required this.onInterestSignal,
    required this.interestConfig,
  });

  final OpportunityRepository opportunityRepository;
  final UserProfile profile;
  final void Function(Opportunity opportunity, InterestSignal signal)?
      onInterestSignal;
  final InterestConfig interestConfig;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
      child: AktionenTab(
        opportunityRepository: opportunityRepository,
        profile: profile,
        onInterestSignal: onInterestSignal,
        interestConfig: interestConfig,
      ),
    );
  }
}

class _WirkungScaffoldTab extends StatelessWidget {
  const _WirkungScaffoldTab();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 20, 18, 28),
      child: WirkungTab(),
    );
  }
}
