import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/mi_theme.dart';
import '../../tracking/domain/action_log.dart';
import '../data/opportunity_relevance_ranker.dart';
import '../domain/interest_config.dart';
import '../domain/interest_weights.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_repository.dart';
import '../domain/user_profile.dart';
import 'action_browser_screen.dart';
import 'hand/hand_view.dart';
import 'letter_screen.dart';
import 'widgets/get_the_app_sheet.dart';

/// Opens an opportunity's source and resolves to true when the user marked
/// it done there.
typedef ActionOpener = Future<bool> Function(
  BuildContext context,
  Opportunity opportunity,
);

/// Opens the letter for a council decision and resolves to true when the
/// user marked it done.
typedef LetterOpener = Future<bool> Function(
  BuildContext context,
  Opportunity opportunity, {
  required OpportunityRepository repository,
  required VoidCallback onViewPaper,
});

/// The "Für dich" tab — the current run's opportunities (see
/// OpportunityRepository.pool, "one run, one feed"), ranked on-device by
/// personal relevance and dealt as a hand of cards (HandView). Fetches the
/// pool once per tab instance; ranking is a pure, cheap client-side
/// transform re-applied whenever the profile changes, not a network
/// concern. Actions the user marked done leave the hand.
class AktionenTab extends StatefulWidget {
  const AktionenTab({
    required this.opportunityRepository,
    required this.profile,
    this.doneIds = const {},
    this.onInterestSignal,
    this.onActionDone,
    this.interestConfig = const InterestConfig(),
    this.openAction = ActionBrowserScreen.open,
    this.openLetter = LetterScreen.open,
    this.isWeb = kIsWeb,
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
  final InterestConfig interestConfig;
  // The in-app browser on Android/iOS; replaceable in tests.
  final ActionOpener openAction;
  // The letter for council decisions; replaceable in tests.
  final LetterOpener openLetter;
  // The web teaser build; replaceable in tests.
  final bool isWeb;

  @override
  State<AktionenTab> createState() => _AktionenTabState();
}

class _AktionenTabState extends State<AktionenTab> {
  late Future<List<RankedOpportunity>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    setState(() {
      // The FutureBuilder only listens from the next frame on; a failure
      // before then is still shown, not reported as unhandled.
      _future = _load()..ignore();
    });
  }

  Future<List<RankedOpportunity>> _load() async {
    final pool = await widget.opportunityRepository.pool();
    final ranker = OpportunityRelevanceRanker(
      interestConfig: widget.interestConfig,
    );
    return ranker.rank(pool, widget.profile);
  }

  // Opens the action; true once the user marked it done. Logging it waits
  // for [_complete], after the card has landed on the Wirkung pile.
  Future<bool> _takeAction(Opportunity opportunity) async {
    // The web build is a teaser: taking part happens in the app.
    if (widget.isWeb) {
      await GetTheAppSheet.show(context);
      return false;
    }
    if (opportunity.kind == OpportunityKind.decision) {
      return widget.openLetter(
        context,
        opportunity,
        repository: widget.opportunityRepository,
        onViewPaper: () => widget.openAction(context, opportunity),
      );
    }
    return widget.openAction(context, opportunity);
  }

  void _complete(Opportunity opportunity) {
    widget.onActionDone?.call(
      opportunity,
      opportunity.kind == OpportunityKind.decision
          ? ActionVia.letter
          : ActionVia.inAppBrowser,
    );
    widget.onInterestSignal?.call(opportunity, InterestSignal.acted);
  }

  @override
  Widget build(BuildContext context) {
    final hand = _buildHand();
    // On the card table already when inside the app shell.
    return Theme.of(context).extension<MiColors>() != null
        ? hand
        : Theme(
            data: miTheme(MediaQuery.platformBrightnessOf(context)),
            child: hand,
          );
  }

  Widget _buildHand() {
    return FutureBuilder<List<RankedOpportunity>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const HandLoading();
        }
        if (snapshot.hasError) {
          debugPrint('Pool loading failed: ${snapshot.error}');
          return HandMessage(
            title: 'Deine Karten konnten nicht geladen werden.',
            body: 'Prüf deine Internetverbindung und versuch es noch einmal.',
            actionLabel: 'Nochmal versuchen',
            onAction: _reload,
          );
        }
        final pool = snapshot.data ?? const <RankedOpportunity>[];
        final opportunities = [
          for (final ranked in pool)
            if (!widget.doneIds.contains(ranked.opportunity.id)) ranked,
        ];
        if (opportunities.isEmpty) {
          return pool.isEmpty
              ? const HandMessage(
                  title: 'Gerade gibt es keine offenen Aktionen.',
                  body: 'Neue kommen dazu, sobald Stadt, Land oder EU sie '
                      'veröffentlichen.',
                )
              : const HandMessage(
                  title: 'Du hast alle Karten gespielt.',
                  body: 'Unter Wirkung siehst du, was aus deinen Aktionen '
                      'wird.',
                );
        }
        return HandView(
          opportunities: opportunities,
          actionLabel: (opportunity) => widget.isWeb
              ? 'In der App mitmachen'
              : opportunity.kind.callToAction,
          onPlay: (ranked) => _takeAction(ranked.opportunity),
          onPlayed: (ranked) => _complete(ranked.opportunity),
          onOpened: (ranked) => widget.onInterestSignal?.call(
            ranked.opportunity,
            InterestSignal.opened,
          ),
        );
      },
    );
  }
}
