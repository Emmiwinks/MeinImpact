import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';
import '../../data/opportunity_relevance_ranker.dart';
import '../../domain/interest_weights.dart';
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
    this.onOption,
    this.doneIds = const {},
    this.onOpened,
    this.onVote,
    this.isFront = true,
    this.contentOpacity = 1,
    this.drift = 0,
    this.peek = false,
    this.onPeeked,
    super.key,
  });

  final RankedOpportunity ranked;
  final String actionLabel;
  // Cards further back in the fan show colour and art, not words.
  final double contentOpacity;
  // Null while the card is not playable (behind the front card, in flight).
  final VoidCallback? onAction;
  // A bundle's option was picked; null while the card is not playable.
  final ValueChanged<RankedOpportunity>? onOption;
  // Done opportunity ids, to tick a bundle's done options.
  final Set<String> doneIds;
  // The card was turned over to its back.
  final VoidCallback? onOpened;
  // "öfter" / "seltener" on the back, for [voteTopic].
  final void Function(String tag, InterestSignal signal)? onVote;
  // Only the front card of the hand reacts to taps.
  final bool isFront;
  // How far the card is from the front of the fan, -1 to 1; the art slides
  // a little against it, so it seems to sit behind the card's window.
  final double drift;
  // Dealt with [peek], the card turns over and back once by itself, so
  // the user sees it has a back; [onPeeked] follows, also when a tap or a
  // swipe cut it short or it never ran.
  final bool peek;
  final VoidCallback? onPeeked;

  @override
  State<ActionCard> createState() => _ActionCardState();
}

// The peek: a moment to land on the table first, a quick turn, long
// enough on the back to see there is more, and back.
const _peekDelay = Duration(milliseconds: 700);
const _peekTurn = Duration(milliseconds: 420);
const _peekHold = Duration(milliseconds: 900);

class _ActionCardState extends State<ActionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn;
  // What the user said about this card's topic, once said.
  InterestSignal? _vote;
  // A finger is on the card; it gives a little under it.
  bool _pressed = false;

  void _press(bool down) {
    // The finger can lift after a swipe has already moved the card on.
    if (mounted && _pressed != down) setState(() => _pressed = down);
  }

  bool get _showsBack => _turn.value > 0.5;

  void _castVote(String tag, InterestSignal signal) {
    setState(() => _vote = signal);
    widget.onVote?.call(tag, signal);
  }

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: MiMotion.flip);
    if (widget.peek) _peekAtBack();
  }

  Future<void> _peekAtBack() async {
    // Told even when the card left the table meanwhile.
    final done = widget.onPeeked;
    await Future<void>.delayed(_peekDelay);
    if (!mounted) {
      done?.call();
      return;
    }
    // Only from face up on the front card, and not when the system asks
    // for no animations.
    if (widget.isFront && _turn.value == 0 && !MiMotion.reduced(context)) {
      try {
        await _turn.animateTo(1, duration: _peekTurn).orCancel;
        await Future<void>.delayed(_peekHold);
        // A tap during the hold already turned it back.
        if (mounted && widget.isFront && _turn.value == 1) {
          await _turn.animateBack(0, duration: _peekTurn).orCancel;
        }
      } on TickerCanceled {
        // A tap or swipe took over.
      }
    }
    done?.call();
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
    final still = MiMotion.reduced(context);
    final card = AnimatedBuilder(
      animation: _turn,
      builder: (context, _) {
        final angle = MiMotion.ease.transform(_turn.value) * pi;
        final back = angle > pi / 2;
        final bundle = widget.ranked.isBundle;
        final face = back
            ? _CardBack(
                ranked: widget.ranked,
                actionLabel: widget.actionLabel,
                onAction: widget.onAction,
                onOption: widget.onOption,
                doneIds: widget.doneIds,
                onTurn: _toggle,
                vote: _vote,
                onVote: widget.onVote == null ? null : _castVote,
              )
            : _CardFront(
                ranked: widget.ranked,
                // A bundle's options are on its back.
                actionLabel: bundle ? 'Optionen ansehen' : widget.actionLabel,
                onAction: bundle
                    ? (widget.isFront ? _toggle : null)
                    : widget.onAction,
                onTurn: widget.isFront ? _toggle : null,
                contentOpacity: widget.contentOpacity,
                drift: still ? 0 : widget.drift.clamp(-1.0, 1.0),
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
    if (!widget.isFront || still) return card;
    return Listener(
      onPointerDown: (_) => _press(true),
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: MiMotion.quick,
        curve: MiMotion.ease,
        child: card,
      ),
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
    required this.drift,
  });

  final RankedOpportunity ranked;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTurn;
  final double contentOpacity;
  final double drift;

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
                    // Drawn a little larger than its window, so the slide
                    // never shows an edge.
                    child: Transform.translate(
                      offset: Offset(-drift * 18, 0),
                      child: Transform.scale(
                        scale: 1.12,
                        child: TopicArt(look: TopicLook.of(opportunity)),
                      ),
                    ),
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
                            cardTitle(ranked),
                            style: fittingTitle(
                              context,
                              cardTitle(ranked),
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
                          cardMetaLine(ranked, DateTime.now()),
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
    required this.onOption,
    required this.doneIds,
    required this.onTurn,
    required this.vote,
    required this.onVote,
  });

  final RankedOpportunity ranked;
  final String actionLabel;
  final VoidCallback? onAction;
  final ValueChanged<RankedOpportunity>? onOption;
  final Set<String> doneIds;
  final VoidCallback onTurn;
  final InterestSignal? vote;
  final void Function(String tag, InterestSignal signal)? onVote;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final opportunity = ranked.opportunity;
    final bundle = ranked.isBundle ? opportunity.bundle : null;
    final look = TopicLook.of(opportunity);
    final facts = factChips(opportunity, DateTime.now());
    final topic = voteTopic(ranked);
    final cast = onVote;
    final voting = topic != null && cast != null;
    // A tap anywhere that is not a button turns the card back over.
    return InkWell(
      onTap: onTurn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: look.face(colors),
            padding: const EdgeInsets.only(left: MiSpace.lg - 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    bundle?.header ??
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
              child: bundle != null
                  ? _BundleContent(
                      summary: bundle.summary,
                      options: ranked.options,
                      doneIds: doneIds,
                      onOption: onOption,
                    )
                  : _BackContent(
                      opportunity: opportunity,
                      facts: facts,
                      text: text,
                      colors: colors,
                    ),
            ),
          ),
          // A bundle's options carry their own way in.
          if (bundle == null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                MiSpace.lg - 4,
                MiSpace.sm,
                MiSpace.lg - 4,
                voting ? 0 : MiSpace.lg - 4,
              ),
              child:
                  FilledButton(onPressed: onAction, child: Text(actionLabel)),
            )
          else if (!voting)
            const SizedBox(height: MiSpace.base),
          if (voting)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MiSpace.base,
                0,
                MiSpace.base,
                MiSpace.xs,
              ),
              child: _TopicVote(
                topic: topic,
                vote: vote,
                onVote: (signal) => cast(topic, signal),
              ),
            ),
        ],
      ),
    );
  }
}

/// The topic a card vote is about: the one the card was ranked up for, or
/// else the card's main topic (the one its art shows).
String? voteTopic(RankedOpportunity ranked) =>
    ranked.interestTag ?? ranked.opportunity.affectedTags.firstOrNull;

/// One quiet line under the action button that names the topic and what a
/// tap changes: "Karten zu Verkehr: öfter · seltener". Once said, the line
/// answers in words; the feed picks the vote up on its next load.
class _TopicVote extends StatelessWidget {
  const _TopicVote({
    required this.topic,
    required this.vote,
    required this.onVote,
  });

  final String topic;
  final InterestSignal? vote;
  final ValueChanged<InterestSignal> onVote;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: colors.onCardMuted);
    final said = vote;
    return SizedBox(
      height: 40,
      child: AnimatedSwitcher(
        duration: MiMotion.reduced(context) ? Duration.zero : MiMotion.flip,
        child: said != null
            ? Row(
                key: const ValueKey('voted'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: colors.onCardMuted,
                  ),
                  const SizedBox(width: MiSpace.xs),
                  Flexible(
                    child: Text(
                      said == InterestSignal.more
                          ? 'Karten zu $topic kommen öfter.'
                          : 'Karten zu $topic kommen seltener.',
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Row(
                key: const ValueKey('ask'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      'Karten zu $topic:',
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _VoteLink(
                    key: const ValueKey('vote-more'),
                    label: 'öfter',
                    style: style,
                    onPressed: () => onVote(InterestSignal.more),
                  ),
                  Text('·', style: style),
                  _VoteLink(
                    key: const ValueKey('vote-less'),
                    label: 'seltener',
                    style: style,
                    onPressed: () => onVote(InterestSignal.less),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A word in the vote line that reads as a link, not a button.
class _VoteLink extends StatelessWidget {
  const _VoteLink({
    required this.label,
    required this.style,
    required this.onPressed,
    super.key,
  });

  final String label;
  final TextStyle? style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.mi.onCardMuted,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: MiSpace.xs + 2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: style?.copyWith(
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: style?.color,
        ),
      ),
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

/// A bundle's back: what it is about, then one block per option with its
/// label, how it differs and its facts. A block opens its option; a done
/// one is ticked and stays, so the others remain one tap away.
class _BundleContent extends StatelessWidget {
  const _BundleContent({
    required this.summary,
    required this.options,
    required this.doneIds,
    required this.onOption,
  });

  final String summary;
  final List<RankedOpportunity> options;
  final Set<String> doneIds;
  final ValueChanged<RankedOpportunity>? onOption;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        MiSpace.lg - 4,
        MiSpace.base,
        MiSpace.lg - 4,
        MiSpace.xl,
      ),
      children: [
        Text(summary, style: text.bodyMedium?.copyWith(color: colors.onCard)),
        for (final option in options) ...[
          const SizedBox(height: MiSpace.md),
          _OptionBlock(
            option: option,
            done: doneIds.contains(option.opportunity.id),
            onOpen: onOption == null ? null : () => onOption!(option),
          ),
        ],
      ],
    );
  }
}

class _OptionBlock extends StatelessWidget {
  const _OptionBlock({
    required this.option,
    required this.done,
    required this.onOpen,
  });

  final RankedOpportunity option;
  final bool done;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final opportunity = option.opportunity;
    final bundle = opportunity.bundle!;
    final facts = optionFacts(opportunity, DateTime.now());
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MiRadius.card - 8),
      side: BorderSide(color: colors.onCard.withValues(alpha: 0.18)),
    );
    return Semantics(
      button: !done,
      label: done ? '${bundle.label}, erledigt' : null,
      child: Material(
        color: Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: done ? null : onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              MiSpace.base,
              MiSpace.md,
              MiSpace.sm,
              MiSpace.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bundle.label,
                        style: text.titleSmall?.copyWith(
                          color: colors.onCard,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bundle.difference,
                        style: text.bodyMedium?.copyWith(color: colors.onCard),
                      ),
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: MiSpace.xs),
                        Text(
                          facts.join(' · '),
                          style: text.labelMedium
                              ?.copyWith(color: colors.onCardMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: MiSpace.sm),
                ExcludeSemantics(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: done ? colors.topics[2] : colors.onCard,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      done ? Icons.check_rounded : Icons.arrow_outward_rounded,
                      size: 20,
                      color: done ? colors.onCard : colors.cardStock,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

/// The card title at the largest step (21, 18, 16, 14) that fits the whole
/// question into [_titleLines] lines and its longest word into one line,
/// so a long question is set smaller rather than cut off, and a long
/// compound ("Informationsfreiheitsgesetz") is not broken mid-word.
TextStyle fittingTitle(
  BuildContext context,
  String title,
  TextStyle base,
  double width,
) {
  final scaler = MediaQuery.textScalerOf(context);
  final longest = title
      .split(RegExp(r'\s+'))
      .fold('', (a, b) => b.length > a.length ? b : a);
  for (final size in const [21.0, 18.0, 16.0, 14.0]) {
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
    final word = TextPainter(
      text: TextSpan(text: longest, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final fits = !painter.didExceedMaxLines && word.width <= width;
    painter.dispose();
    word.dispose();
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

/// The card's question: a bundle's shared one, else its own.
String cardTitle(RankedOpportunity ranked) => ranked.isBundle
    ? ranked.opportunity.bundle!.title
    : ranked.opportunity.title;

/// [metaLine], and for a bundle its number of options and the soonest
/// deadline among them, e.g. "2 Optionen · noch 3 Tage".
String cardMetaLine(RankedOpportunity ranked, DateTime now) {
  if (!ranked.isBundle) return metaLine(ranked.opportunity, now);
  final options = [for (final o in ranked.options) o.opportunity];
  int order(Opportunity o) => o.daysLeft(now) ?? 1 << 30;
  final soonest = options.reduce((a, b) => order(b) < order(a) ? b : a);
  final when = _when(soonest, now);
  final count = '${options.length} Optionen';
  return when == null ? count : '$count · $when';
}

/// One option's own facts on a bundle's back: its deadline and support.
List<String> optionFacts(Opportunity opportunity, DateTime now) {
  final closesOn = opportunity.closesOn;
  final support = opportunity.supportCount;
  return [
    if (closesOn != null && opportunity.daysLeft(now) != null)
      opportunity.kind == OpportunityKind.decision
          ? 'Sitzung am ${_date(closesOn)}'
          : 'bis ${_date(closesOn)}',
    if (support != null) '${thousands(support)} Unterstützer:innen',
  ];
}

/// Kind and timing in one line, e.g. "Petition · noch 12 Tage".
String metaLine(Opportunity opportunity, DateTime now) {
  final when = _when(opportunity, now);
  return when == null
      ? opportunity.kind.label
      : '${opportunity.kind.label} · $when';
}

String? _when(Opportunity opportunity, DateTime now) {
  final opensOn = opportunity.opensOn;
  final daysLeft = opportunity.daysLeft(now);
  return opportunity.isAnnounced && opensOn != null
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
          ? '${thousands(support)} von ${thousands(goal)} Unterstützer:innen'
          : '${thousands(support)} Unterstützer:innen',
    if (place != null) place,
    ...opportunity.districts,
  ];
}

String _date(DateTime date) => '${date.day}.${date.month}.${date.year}';

/// A count the German way, with points between thousands: 692.334.
String thousands(int count) {
  final digits = count.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  return count < 0 ? '-$grouped' : grouped.toString();
}
