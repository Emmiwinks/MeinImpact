import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../features/feed/domain/betroffenheitsprofil.dart';
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
    this.onBetroffenheitsprofilChanged,
    super.key,
  });

  final OpportunityRepository opportunityRepository;
  final UserProfile? profile;
  final VoidCallback? onEditProfile;
  final ValueChanged<Betroffenheitsprofil>? onBetroffenheitsprofilChanged;

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
        onBetroffenheitsprofilChanged: widget.onBetroffenheitsprofilChanged,
      ),
      _AktionenScaffoldTab(
        opportunityRepository: widget.opportunityRepository,
        profile: effectiveProfile,
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
    required this.onBetroffenheitsprofilChanged,
  });

  final UserProfile profile;
  final VoidCallback? onEdit;
  final ValueChanged<Betroffenheitsprofil>? onBetroffenheitsprofilChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
      child: ProfileColumn(
        profile: profile,
        onEdit: onEdit ?? () {},
        onBetroffenheitsprofilChanged: onBetroffenheitsprofilChanged ?? (_) {},
      ),
    );
  }
}

class _AktionenScaffoldTab extends StatelessWidget {
  const _AktionenScaffoldTab({
    required this.opportunityRepository,
    required this.profile,
  });

  final OpportunityRepository opportunityRepository;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
      child: AktionenTab(
        opportunityRepository: opportunityRepository,
        profile: profile,
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
