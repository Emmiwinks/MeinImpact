import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../tracking/domain/action_log.dart';
import '../data/opportunity_relevance_ranker.dart';
import '../domain/interest_config.dart';
import '../domain/interest_weights.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_repository.dart';
import '../domain/user_profile.dart';
import 'action_browser_screen.dart';
import 'widgets/action_done_sheet.dart';
import 'widgets/feed_error.dart';
import 'widgets/loading_card.dart';
import 'widgets/opportunity_detail_dialog.dart';
import 'widgets/opportunity_panel.dart';

/// Opens an opportunity's source and resolves to true when the user marked
/// it done there.
typedef ActionOpener = Future<bool> Function(
  BuildContext context,
  Opportunity opportunity,
);

/// The "Aktionen" tab — the current run's opportunities (see
/// OpportunityRepository.pool, "one run, one feed"), ranked on-device by
/// personal relevance. Fetches the pool once per tab instance; ranking is
/// a pure, cheap client-side transform re-applied whenever the profile
/// changes, not a network concern. Actions the user marked done leave the
/// feed.
class AktionenTab extends StatefulWidget {
  const AktionenTab({
    required this.opportunityRepository,
    required this.profile,
    this.doneIds = const {},
    this.onInterestSignal,
    this.onActionDone,
    this.onActionUndone,
    this.interestConfig = const InterestConfig(),
    this.openAction = ActionBrowserScreen.open,
    super.key,
  });

  final OpportunityRepository opportunityRepository;
  final UserProfile profile;
  // Opportunity ids in the action log; hidden from the feed.
  final Set<String> doneIds;
  // Reports what the user did with an opportunity, for learning interests.
  final void Function(Opportunity opportunity, InterestSignal signal)?
      onInterestSignal;
  final void Function(Opportunity opportunity, ActionVia via)? onActionDone;
  final ValueChanged<String>? onActionUndone;
  final InterestConfig interestConfig;
  // The in-app browser on Android/iOS; replaceable in tests.
  final ActionOpener openAction;

  @override
  State<AktionenTab> createState() => _AktionenTabState();
}

class _AktionenTabState extends State<AktionenTab> {
  late Future<List<RankedOpportunity>> _future;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RankedOpportunity>> _load() async {
    final pool = await widget.opportunityRepository.pool();
    final ranker = OpportunityRelevanceRanker(
      interestConfig: widget.interestConfig,
    );
    return ranker.rank(pool, widget.profile);
  }

  void _open(List<RankedOpportunity> opportunities, int index) {
    setState(() => _selectedIndex = index);
    final l10n = AppLocalizations.of(context);
    final opportunity = opportunities[index].opportunity;
    widget.onInterestSignal?.call(opportunity, InterestSignal.opened);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => OpportunityDetailDialog(
        l10n: l10n,
        ranked: opportunities[index],
        onTakeAction: () => _takeAction(opportunity),
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedIndex = null);
    });
  }

  Future<void> _takeAction(Opportunity opportunity) async {
    if (kIsWeb) {
      // Action sites refuse to be framed, so the web build opens a new tab
      // and offers "Fertig" for when the user comes back.
      final uri = Uri.tryParse(opportunity.sourceUrl);
      if (uri == null) return;
      await launchUrl(uri, webOnlyWindowName: '_blank');
      if (mounted && opportunity.kind.completesInBrowser) {
        _showReturnBanner(opportunity, uri.host);
      }
      return;
    }
    final done = await widget.openAction(context, opportunity);
    if (done && mounted) await _complete(opportunity, ActionVia.inAppBrowser);
  }

  void _showReturnBanner(Opportunity opportunity, String host) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text('Zurück von $host? Wenn du mitgemacht hast: Fertig.'),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Später'),
          ),
          FilledButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              if (mounted) _complete(opportunity, ActionVia.webReturn);
            },
            child: const Text('Fertig'),
          ),
        ],
      ),
    );
  }

  // Logs the action first, so the feed drops it while the sheet is up.
  // Interest learning waits for the sheet, so an undo leaves no trace.
  Future<void> _complete(Opportunity opportunity, ActionVia via) async {
    widget.onActionDone?.call(opportunity, via);
    final undone = await ActionDoneSheet.show(context, opportunity);
    if (undone) {
      widget.onActionUndone?.call(opportunity.id);
    } else {
      widget.onInterestSignal?.call(opportunity, InterestSignal.acted);
    }
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
        final opportunities = [
          for (final ranked in snapshot.data ?? const <RankedOpportunity>[])
            if (!widget.doneIds.contains(ranked.opportunity.id)) ranked,
        ];
        return OpportunityPanel(
          opportunities: opportunities,
          selectedIndex: _selectedIndex ?? -1,
          onSelect: (index) => _open(opportunities, index),
        );
      },
    );
  }
}
