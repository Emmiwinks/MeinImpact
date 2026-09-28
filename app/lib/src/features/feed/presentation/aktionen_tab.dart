import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import '../data/opportunity_relevance_ranker.dart';
import '../domain/opportunity_repository.dart';
import '../domain/user_profile.dart';
import 'widgets/feed_error.dart';
import 'widgets/loading_card.dart';
import 'widgets/opportunity_detail_dialog.dart';
import 'widgets/opportunity_panel.dart';

/// The "Aktionen" tab — the current run's opportunities (see
/// OpportunityRepository.pool, "one run, one feed"), ranked on-device by
/// personal relevance. Fetches the pool once per tab instance; ranking is
/// a pure, cheap client-side transform re-applied whenever the profile
/// changes, not a network concern.
class AktionenTab extends StatefulWidget {
  const AktionenTab({
    required this.opportunityRepository,
    required this.profile,
    super.key,
  });

  final OpportunityRepository opportunityRepository;
  final UserProfile profile;

  @override
  State<AktionenTab> createState() => _AktionenTabState();
}

class _AktionenTabState extends State<AktionenTab> {
  static const _ranker = OpportunityRelevanceRanker();

  late Future<List<RankedOpportunity>> _future;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RankedOpportunity>> _load() async {
    final pool = await widget.opportunityRepository.pool();
    return _ranker.rank(pool, widget.profile);
  }

  void _open(List<RankedOpportunity> opportunities, int index) {
    setState(() => _selectedIndex = index);
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => OpportunityDetailDialog(
        l10n: l10n,
        ranked: opportunities[index],
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedIndex = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RankedOpportunity>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingCard();
        }
        if (snapshot.hasError) {
          return FeedError(message: snapshot.error.toString());
        }
        final opportunities = snapshot.data ?? const [];
        return OpportunityPanel(
          opportunities: opportunities,
          selectedIndex: _selectedIndex ?? -1,
          onSelect: (index) => _open(opportunities, index),
        );
      },
    );
  }
}
