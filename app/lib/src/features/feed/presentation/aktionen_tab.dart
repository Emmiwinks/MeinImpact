import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/mi_theme.dart';
import '../../../core/feedback/beta_feedback.dart';
import '../../../core/usage/usage.dart';
import '../../feedback/feedback_sheets.dart';
import '../../notifications/notifications.dart';
import '../../tracking/domain/action_log.dart';
import '../../tracking/domain/progress.dart';
import '../../tracking/streak_flame.dart';
import '../data/bundled_cards.dart';
import '../data/hand_hints.dart';
import '../data/hand_mix.dart';
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
/// transform, re-applied to that pool when [profileRevision] changes (a
/// profile edit), not on learned interest signals, so the hand does not
/// shuffle under the user's finger. Actions the user marked done leave the
/// hand.
class AktionenTab extends StatefulWidget {
  const AktionenTab({
    required this.opportunityRepository,
    required this.profile,
    this.profileRevision = 0,
    this.doneIds = const {},
    this.streak,
    this.onInterestSignal,
    this.onActionDone,
    this.interestConfig = const InterestConfig(),
    this.openAction = ActionBrowserScreen.open,
    this.openLetter = LetterScreen.open,
    this.dismissedIds = const {},
    this.onDismissed,
    this.isWeb = kIsWeb,
    super.key,
  });

  final OpportunityRepository opportunityRepository;
  final UserProfile profile;
  // Bumped by each profile edit; the hand re-ranks the loaded pool.
  final int profileRevision;
  // Opportunity ids in the action log; hidden from the feed.
  final Set<String> doneIds;
  // The flame top right; none without it.
  final Streak? streak;
  // Reports what the user did with topics (a card's tags, or the one topic
  // of a card vote), for learning interests.
  final void Function(List<String> tags, InterestSignal signal)?
      onInterestSignal;
  final void Function(Opportunity opportunity, ActionVia via)? onActionDone;
  final InterestConfig interestConfig;
  // The in-app browser on Android/iOS; replaceable in tests.
  final ActionOpener openAction;
  // The letter for council decisions; replaceable in tests.
  final LetterOpener openLetter;
  // Opportunity ids thrown away from the hand: never dealt again.
  final Set<String> dismissedIds;
  // Ids just thrown away, to keep.
  final ValueChanged<Set<String>>? onDismissed;
  // The web teaser build; replaceable in tests.
  final bool isWeb;

  @override
  State<AktionenTab> createState() => _AktionenTabState();
}

class _AktionenTabState extends State<AktionenTab> with WidgetsBindingObserver {
  late Future<List<RankedOpportunity>> _future;
  // The fetched pool, kept so a profile edit re-ranks without a refetch.
  List<Opportunity>? _pool;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _load();
  }

  @override
  void didUpdateWidget(AktionenTab old) {
    super.didUpdateWidget(old);
    final pool = _pool;
    if (widget.profileRevision != old.profileRevision && pool != null) {
      _future = Future.value(_rank(pool));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the background (often with the network back too), a failed
  // hand tries again by itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loadFailed) _reload();
  }

  void _reload() {
    setState(() {
      // The FutureBuilder only listens from the next frame on; a failure
      // before then is still shown, not reported as unhandled.
      _future = _load()..ignore();
    });
  }

  Future<List<RankedOpportunity>> _load() async {
    _loadFailed = false;
    try {
      final pool = await widget.opportunityRepository.pool(
        kreis: widget.profile.home?.kreis,
      );
      _pool = pool;
      return _rank(pool);
    } catch (_) {
      _loadFailed = true;
      rethrow;
    }
  }

  List<RankedOpportunity> _rank(List<Opportunity> pool) =>
      widget.profile.browsing
          ? shuffledPool(pool)
          : OpportunityRelevanceRanker(interestConfig: widget.interestConfig)
              .rank(pool, widget.profile);

  // Opens the action; true once the user marked it done. Logging it waits
  // for [_complete], after the card has landed on the Wirkung pile.
  Future<bool> _takeAction(Opportunity opportunity) async {
    // The web build is a teaser: taking part happens in the app.
    if (widget.isWeb) {
      await GetTheAppSheet.show(context);
      return false;
    }
    Usage.current.count(UsageEvent.actionOpened);
    if (opportunity.kind == OpportunityKind.decision) {
      return widget.openLetter(
        context,
        opportunity,
        repository: widget.opportunityRepository,
        onViewPaper: () => widget.openAction(context, opportunity),
      );
    }
    final done = await widget.openAction(context, opportunity);
    // Left without "Fertig": maybe they took part anyway, so ask tomorrow.
    if (!done) Notifications.current.lookedAt(opportunity, openedSite: true);
    return done;
  }

  void _complete(Opportunity opportunity) {
    widget.onActionDone?.call(
      opportunity,
      opportunity.kind == OpportunityKind.decision
          ? ActionVia.letter
          : ActionVia.inAppBrowser,
    );
    widget.onInterestSignal
        ?.call(opportunity.affectedTags, InterestSignal.acted);
  }

  // A card pulled off the hand: why, if the user says. Resolves to false
  // when they keep it after all.
  Future<bool> _throwAway(RankedOpportunity ranked, int position) async {
    final verdict = await showCardReasonSheet(context);
    if (verdict?.keep ?? false) return false;
    Usage.current.count(UsageEvent.cardDismissed);
    final opportunity = ranked.opportunity;
    // A bundle goes with all its options.
    widget.onDismissed?.call(
      ranked.isBundle
          ? {for (final o in ranked.options) o.opportunity.id}
          : {opportunity.id},
    );
    final reason = verdict?.reason;
    if (reason == null) return true;
    BetaFeedback.current.card(
      opportunityId: opportunity.id,
      reason: reason,
      note: verdict?.note,
      ranking: ranked.parts.toFeedback(position: position),
    );
    if (reason == CardReason.notInterested) {
      widget.onInterestSignal
          ?.call(opportunity.affectedTags, InterestSignal.notInterested);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final hand = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cold wood before the first action says nothing yet: the flame
        // shows once there is something to keep burning.
        _TopLine(streak: widget.doneIds.isEmpty ? null : widget.streak),
        Expanded(child: _buildHand()),
      ],
    );
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
        // Mixed after the done ones are out, so the hand on screen is mixed
        final opportunities = mixHand(
          bundleCards(
            [
              for (final r in pool)
                if (!widget.dismissedIds.contains(r.opportunity.id)) r,
            ],
            doneIds: widget.doneIds,
          ),
          handSize: kHandSize,
          anyLocal: widget.profile.browsing,
        );
        if (opportunities.isEmpty) {
          return pool.isEmpty
              ? const HandMessage(
                  title: 'Gerade gibt es keine offenen Aktionen.',
                  body: 'Neue kommen dazu, sobald Region, Land oder EU sie '
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
          doneIds: widget.doneIds,
          actionLabel: (opportunity) => widget.isWeb
              ? 'In der App mitmachen'
              : opportunity.kind.callToAction,
          onPlay: (ranked) => _takeAction(ranked.opportunity),
          onPlayed: (ranked) => _complete(ranked.opportunity),
          onOpened: (ranked) {
            Usage.current.count(UsageEvent.cardTurned);
            HandHints.current.markTurnSeen();
            Notifications.current.lookedAt(ranked.opportunity);
            widget.onInterestSignal?.call(
              ranked.opportunity.affectedTags,
              InterestSignal.opened,
            );
          },
          // The web teaser has no feedback to collect.
          onThrow: widget.isWeb ? null : _throwAway,
          throwHint: widget.dismissedIds.isEmpty,
          turnHint: !HandHints.current.turnSeen,
          onTurnHinted: HandHints.current.markTurnSeen,
        );
      },
    );
  }
}

/// Above the hand: the streak, top right. The row keeps its height without
/// it, so the hand does not move when the flame first appears.
class _TopLine extends StatelessWidget {
  const _TopLine({required this.streak});

  final Streak? streak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MiSpace.lg,
        MiSpace.sm,
        MiSpace.base,
        0,
      ),
      child: SizedBox(
        height: 48,
        child: Align(
          alignment: Alignment.centerRight,
          child: streak == null ? null : StreakFlame(streak: streak!),
        ),
      ),
    );
  }
}
