import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../data/opportunity_relevance_ranker.dart';
import '../../domain/lebenslage.dart';
import '../../domain/opportunity.dart';
import 'topic_art.dart';

/// One action as a playing card. The front says what it is and why it is
/// yours; tapping turns it over to the facts and both sides of the
/// argument. The action button sits on both faces.
class ActionCard extends StatefulWidget {
  const ActionCard({
    required this.ranked,
    required this.actionLabel,
    this.onAction,
    this.onOpened,
    this.isFront = true,
    this.contentOpacity = 1,
    super.key,
  });

  final RankedOpportunity ranked;
  final String actionLabel;
  // Cards further back in the fan show colour and art, not words.
  final double contentOpacity;
  // Null while the card is not playable (behind the front card, in flight).
  final VoidCallback? onAction;
  // The card was turned over to its back.
  final VoidCallback? onOpened;
  // Only the front card of the hand reacts to taps.
  final bool isFront;

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn;

  bool get _showsBack => _turn.value > 0.5;

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: MiMotion.flip);
  }

  @override
  void didUpdateWidget(ActionCard old) {
    super.didUpdateWidget(old);
    // A card that leaves the front lies face up again.
    if (!widget.isFront && _turn.value != 0) _turn.value = 0;
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _toggle() {
    final toBack = !_showsBack;
    if (MiMotion.reduced(context)) {
      _turn.value = toBack ? 1 : 0;
    } else if (toBack) {
      _turn.forward();
    } else {
      _turn.reverse();
    }
    if (toBack) widget.onOpened?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return AnimatedBuilder(
      animation: _turn,
      builder: (context, _) {
        final angle = MiMotion.ease.transform(_turn.value) * pi;
        final back = angle > pi / 2;
        final face = back
            ? _CardBack(
                ranked: widget.ranked,
                actionLabel: widget.actionLabel,
                onAction: widget.onAction,
                onTurn: _toggle,
              )
            : _CardFront(
                ranked: widget.ranked,
                actionLabel: widget.actionLabel,
                onAction: widget.onAction,
                onTurn: widget.isFront ? _toggle : null,
                contentOpacity: widget.contentOpacity,
              );
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(back ? pi : 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MiRadius.card),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Material(
                color: colors.cardStock,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MiRadius.card),
                  side: BorderSide(color: colors.keyline),
                ),
                clipBehavior: Clip.antiAlias,
                child: face,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({
    required this.ranked,
    required this.actionLabel,
    required this.onAction,
    required this.onTurn,
    required this.contentOpacity,
  });

  final RankedOpportunity ranked;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTurn;
  final double contentOpacity;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final opportunity = ranked.opportunity;
    final why = whyLine(ranked);
    return InkWell(
      onTap: onTurn,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inner = constraints.maxWidth - 2 * (MiSpace.lg - 4);
          // The art takes what the words leave over, never less than a
          // band; the words never push it out. Set in a margin of card
          // stock, like the picture on a playing card.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MiSpace.md - 2,
                    MiSpace.md - 2,
                    MiSpace.md - 2,
                    0,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(MiRadius.card - 8),
                    child: TopicArt(look: TopicLook.of(opportunity)),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: max(0, constraints.maxHeight - 72),
                ),
                child: Opacity(
                  opacity: contentOpacity,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MiSpace.lg - 4,
                      MiSpace.base + 2,
                      MiSpace.lg - 4,
                      MiSpace.lg - 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            opportunity.title,
                            style: fittingTitle(
                              context,
                              opportunity.title,
                              text.titleLarge!.copyWith(color: colors.onCard),
                              inner,
                            ),
                            maxLines: _titleLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (why != null) ...[
                          const SizedBox(height: MiSpace.sm),
                          Text(
                            why,
                            style:
                                text.bodyLarge?.copyWith(color: colors.onCard),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: MiSpace.base),
                        Text(
                          metaLine(opportunity, DateTime.now()),
                          style: text.labelMedium?.copyWith(
                            color: colors.onCardMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: MiSpace.md),
                        FilledButton(
                          onPressed: onAction,
                          child: Text(actionLabel, textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({
    required this.ranked,
    required this.actionLabel,
    required this.onAction,
    required this.onTurn,
  });

  final RankedOpportunity ranked;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onTurn;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final opportunity = ranked.opportunity;
    final look = TopicLook.of(opportunity);
    final facts = factChips(opportunity, DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: look.face(colors),
          padding: const EdgeInsets.only(left: MiSpace.lg - 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${opportunity.kind.label} · ${opportunity.sourceOrg}',
                  style: text.labelMedium?.copyWith(color: colors.onCard),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: onTurn,
                tooltip: 'Karte umdrehen',
                color: colors.onCard,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          // Fades out at the bottom edge, so more below the button reads
          // as scrollable rather than cut off.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0, 0.86, 1],
            ).createShader(bounds),
            child: _BackContent(
              opportunity: opportunity,
              facts: facts,
              text: text,
              colors: colors,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MiSpace.lg - 4,
            MiSpace.xs,
            MiSpace.lg - 4,
            MiSpace.lg - 4,
          ),
          child: FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      ],
    );
  }
}

class _BackContent extends StatelessWidget {
  const _BackContent({
    required this.opportunity,
    required this.facts,
    required this.text,
    required this.colors,
  });

  final Opportunity opportunity;
  final List<String> facts;
  final TextTheme text;
  final MiColors colors;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        MiSpace.lg - 4,
        MiSpace.base,
        MiSpace.lg - 4,
        MiSpace.xl,
      ),
      children: [
        Text(
          opportunity.summary,
          style: text.bodyMedium?.copyWith(color: colors.onCard),
        ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: MiSpace.md),
          Wrap(
            spacing: MiSpace.sm,
            runSpacing: MiSpace.sm,
            children: [for (final fact in facts) _FactChip(fact)],
          ),
        ],
        if (opportunity.proArgumente.isNotEmpty)
          _Arguments(
            title: 'Dafür spricht',
            points: opportunity.proArgumente,
          ),
        if (opportunity.contraArgumente.isNotEmpty)
          _Arguments(
            title: 'Dagegen spricht',
            points: opportunity.contraArgumente,
          ),
      ],
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MiSpace.md,
        vertical: MiSpace.xs + 2,
      ),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: colors.onCard)),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: colors.onCard),
      ),
    );
  }
}

class _Arguments extends StatelessWidget {
  const _Arguments({required this.title, required this.points});

  final String title;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: MiSpace.lg - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.titleMedium?.copyWith(color: colors.onCard),
          ),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(top: MiSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: MiSpace.sm),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.onCard,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      point,
                      style: text.bodyMedium?.copyWith(color: colors.onCard),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const _titleLines = 5;

/// The card title at the largest step (21, 18, 16) that fits the whole
/// question into [_titleLines] lines, so a long question is set smaller
/// rather than cut off.
TextStyle fittingTitle(
  BuildContext context,
  String title,
  TextStyle base,
  double width,
) {
  final scaler = MediaQuery.textScalerOf(context);
  for (final size in const [21.0, 18.0, 16.0]) {
    final style = base.copyWith(
      fontSize: size,
      letterSpacing: -0.02 * size,
    );
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: _titleLines,
    )..layout(maxWidth: width);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    if (fits) return style;
  }
  return base.copyWith(fontSize: 16, letterSpacing: -0.32);
}

/// Why this card is in the user's hand: the personal sentence enrichment
/// wrote for their situation, else the picked Lebenslage, else a learned
/// topic interest. A private Lebenslage is never named on a card.
String? whyLine(RankedOpportunity ranked) {
  if (ranked.matchedSnippet case final snippet?) return snippet;
  final lebenslage = lebenslageById[ranked.matchedLebenslage];
  if (lebenslage != null) {
    // The catalog label quoted as the user picked it, so every one of the
    // labels reads as a reason without a hand-written sentence each.
    return lebenslage.isPrivate
        ? 'Weil es zu deinen Angaben passt'
        : 'Weil du „${lebenslage.label}“ angegeben hast';
  }
  final tag = ranked.interestTag;
  return tag != null ? 'Weil du dich für $tag interessierst' : null;
}

/// Kind and timing in one line, e.g. "Petition · noch 12 Tage".
String metaLine(Opportunity opportunity, DateTime now) {
  final opensOn = opportunity.opensOn;
  final daysLeft = opportunity.daysLeft(now);
  final when = opportunity.isAnnounced && opensOn != null
      ? 'ab ${_date(opensOn)}'
      : daysLeft == null
          ? null
          // "Abstimmung im Rat" already names the vote.
          : opportunity.kind == OpportunityKind.decision
              ? switch (daysLeft) {
                  0 => 'heute',
                  1 => 'morgen',
                  _ => 'in $daysLeft Tagen',
                }
              : switch (daysLeft) {
                  0 => 'endet heute',
                  1 => 'noch 1 Tag',
                  _ => 'noch $daysLeft Tage',
                };
  return when == null
      ? opportunity.kind.label
      : '${opportunity.kind.label} · $when';
}

/// Registry facts for the card's back. Support is informational only, never
/// a ranking claim.
List<String> factChips(Opportunity opportunity, DateTime now) {
  final opensOn = opportunity.opensOn;
  final closesOn = opportunity.closesOn;
  final support = opportunity.supportCount;
  final goal = opportunity.supportGoal;
  final place = opportunity.organizer ?? opportunity.locality;
  return [
    if (opportunity.isAnnounced && opensOn != null) 'Ab ${_date(opensOn)}',
    if (closesOn != null && opportunity.daysLeft(now) != null)
      opportunity.kind == OpportunityKind.decision
          ? 'Sitzung am ${_date(closesOn)}'
          : 'Bis ${_date(closesOn)}',
    if (support != null)
      goal != null
          ? '$support von $goal Unterstützer:innen'
          : '$support Unterstützer:innen',
    if (place != null) place,
    ...opportunity.districts,
  ];
}

String _date(DateTime date) => '${date.day}.${date.month}.${date.year}';
