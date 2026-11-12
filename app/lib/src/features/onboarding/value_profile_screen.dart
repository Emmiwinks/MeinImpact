import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/mi_theme.dart';
import '../feed/domain/user_profile.dart';
import '../feed/presentation/widgets/axis_track.dart';
import '../feed/presentation/widgets/werte_bild.dart';

// The two statements of each question, in werteQuestionKeys order: the
// left one pulls towards -2, the right one towards +2.
const _kStatements = [
  (
    'Der Staat sollte große Vermögen und Einkommen stärker ausgleichen.',
    'Wer Leistung bringt, sollte davon profitieren, mit möglichst wenig '
        'staatlichem Eingriff.',
  ),
  (
    'Der Staat muss Märkte regulieren und wichtige Bereiche selbst '
        'kontrollieren.',
    'Privatwirtschaft und Wettbewerb lösen Probleme besser als der Staat.',
  ),
  (
    'Deutschland sollte seine eigenen Interessen klar vertreten, auch wenn '
        'das Partner vor den Kopf stößt.',
    'Globale Probleme lassen sich nur gemeinsam lösen. Nationale '
        'Alleingänge bringen nichts.',
  ),
  (
    'Deutschland sollte außenpolitisch unabhängiger werden und weniger '
        'Verpflichtungen eingehen.',
    'Deutschland muss mehr globale Verantwortung übernehmen, auch wenn das '
        'kostet.',
  ),
  (
    'Der Staat soll so wenig wie möglich in das Leben der Menschen '
        'eingreifen.',
    'Mehr staatliche Regeln und Kontrolle sind nötig, um Sicherheit und '
        'Zusammenhalt zu gewährleisten.',
  ),
  (
    'Im Zweifel sind Bürgerrechte wichtiger als staatliche '
        'Sicherheitsinteressen.',
    'Im Zweifel ist Sicherheit wichtiger als individuelle Freiheiten.',
  ),
  (
    'Gesellschaftliche Strukturen, die sich bewährt haben, sollten erhalten '
        'bleiben.',
    'Die Gesellschaft muss sich mutig weiterentwickeln, auch wenn das '
        'unbequem ist.',
  ),
  (
    'Wir fordern zu viel von der heutigen Generation für Probleme, die erst '
        'in der Zukunft spürbar werden.',
    'Ich bin bereit, heute auf Komfort zu verzichten, damit zukünftige '
        'Generationen es besser haben.',
  ),
];

// Within this distance of the centre the answer snaps to "beides gleich".
const _kDetent = 0.14;

// How long dealing the next question card takes.
const _kDeal = Duration(milliseconds: 460);

/// The values questionnaire. "Dein Bild" sits on top and builds with every
/// answer; below it one question card at a time holds both statements side
/// by side and, in the axis colour, a continuous slider between them. After
/// the last question the picture is framed and revealed.
class ValueProfileScreen extends StatefulWidget {
  const ValueProfileScreen({
    required this.onComplete,
    this.onUseExampleProfile,
    this.initial = const {},
    super.key,
  });

  /// The answered questions only; skipped ones stay out (they count as 0).
  final void Function(Map<String, double> werte) onComplete;

  /// Shortcut shown only during first-time setup (null when re-doing the
  /// quiz from an existing profile) — fills every question neutral and
  /// hands off to a hardcoded example set of Lebenslagen instead.
  final VoidCallback? onUseExampleProfile;

  /// Earlier answers to start from when re-doing the questionnaire.
  final Map<String, double> initial;

  @override
  State<ValueProfileScreen> createState() => _ValueProfileScreenState();
}

class _ValueProfileScreenState extends State<ValueProfileScreen>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late final List<double?> _answers = [
    for (final key in werteQuestionKeys) widget.initial[key],
  ];

  // The reveal: the question fades away, the picture grows to the middle
  // and a frame grows around it, then its title comes in.
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _revealing = false;
  DateTime _revealedAt = DateTime.now();
  // Which way the cards are dealt: on to the next question, or back.
  bool _forward = true;

  static const _fadeOut = Interval(0, 0.3, curve: Curves.easeIn);
  static const _grow = Interval(0.1, 0.65, curve: MiMotion.ease);
  static const _frame = Interval(0.45, 0.85, curve: MiMotion.ease);
  static const _titleIn = Interval(0.7, 1, curve: MiMotion.ease);

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  void _answer(double value) {
    var v = (value.clamp(-2.0, 2.0) * 100).round() / 100;
    if (v.abs() < _kDetent) v = 0;
    final before = _answers[_step];
    if (before == v) return;
    // A click on the first answer and each time it snaps to the centre.
    if (before == null || (v == 0 && before != 0)) {
      HapticFeedback.selectionClick();
    }
    setState(() => _answers[_step] = v);
  }

  // Skipping and moving on without an answer are the same: the key stays
  // absent (0 in the profile).
  void _next() {
    if (_step < _kStatements.length - 1) {
      setState(() {
        _forward = true;
        _step++;
      });
    } else {
      _finish();
    }
  }

  void _finish() {
    // Nothing answered, nothing to frame.
    if (_answers.every((a) => a == null)) {
      _done();
      return;
    }
    setState(() {
      _revealing = true;
      _revealedAt = DateTime.now();
    });
    if (MiMotion.reduced(context)) {
      _reveal.value = 1;
      return;
    }
    _reveal.forward(from: 0);
    // A soft knock when the frame closes around the picture.
    Timer(const Duration(milliseconds: 900), () {
      if (mounted && _revealing) HapticFeedback.lightImpact();
    });
  }

  void _change() {
    setState(() {
      _revealing = false;
      _forward = false;
      _step = 0;
    });
    if (MiMotion.reduced(context)) {
      _reveal.value = 0;
    } else {
      _reveal.reverse();
    }
  }

  void _done() {
    widget.onComplete({
      for (var i = 0; i < werteQuestionKeys.length; i++)
        if (_answers[i] != null) werteQuestionKeys[i]: _answers[i]!,
    });
  }

  // System back steps back through the questions (and out of the reveal)
  // before it leaves the questionnaire.
  void _back() {
    if (_revealing) {
      setState(() => _revealing = false);
      if (MiMotion.reduced(context)) {
        _reveal.value = 0;
      } else {
        _reveal.reverse();
      }
    } else if (_step > 0) {
      setState(() {
        _forward = false;
        _step--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final isLast = _step == _kStatements.length - 1;

    return PopScope(
      canPop: !_revealing && _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: colors.table,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _reveal,
            builder: (context, _) {
              final r = _reveal.value;
              final away = _fadeOut.transform(r);
              final titleIn = _titleIn.transform(r);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IgnorePointer(
                    ignoring: _revealing,
                    child: Opacity(
                      opacity: 1 - away,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          MiSpace.lg,
                          MiSpace.sm,
                          MiSpace.sm,
                          0,
                        ),
                        child: SizedBox(
                          height: 48,
                          child: Row(
                            children: [
                              Expanded(
                                child: _Progress(
                                  count: _kStatements.length,
                                  step: _step,
                                ),
                              ),
                              if (!isLast)
                                TextButton(
                                  onPressed: _next,
                                  style: TextButton.styleFrom(
                                    foregroundColor: colors.onTableMuted,
                                  ),
                                  child: const Text('Überspringen'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => _stage(context, box, r),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      MiSpace.lg,
                      MiSpace.sm,
                      MiSpace.lg,
                      MiSpace.base,
                    ),
                    child: _revealing
                        ? IgnorePointer(
                            ignoring: r < 1,
                            child: Opacity(
                              opacity: titleIn,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FilledButton(
                                    onPressed: _done,
                                    style: colors.tableButton,
                                    child: const Text('Weiter'),
                                  ),
                                  const SizedBox(height: MiSpace.sm),
                                  OutlinedButton(
                                    onPressed: _change,
                                    child: const Text('Antworten ändern'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Opacity(
                            opacity: 1 - away,
                            child: FilledButton(
                              onPressed: _next,
                              style: colors.tableButton,
                              child: Text(isLast ? 'Fertig' : 'Weiter'),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The picture and, below it, the question; during the reveal the
  /// question fades out and the picture grows into its frame in the middle.
  Widget _stage(BuildContext context, BoxConstraints box, double r) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final width = box.maxWidth;
    final height = box.maxHeight;
    const framing = (WerteBildRahmen.frame + WerteBildRahmen.mat) * 2;
    const titleBlock = 120.0;

    final small = math.min((height * 0.34).clamp(120.0, 240.0), width - 96);
    final big = math.min(
      math.min(width - MiSpace.lg * 2 - framing, height - titleBlock - framing),
      300.0,
    );
    final bigTop =
        math.max(MiSpace.base, (height - big - framing - titleBlock) / 2);

    final away = _fadeOut.transform(r);
    final grow = _grow.transform(r);
    final frame = _frame.transform(r);
    final titleIn = _titleIn.transform(r);
    final size = lerpDouble(small, big, grow)!;
    final outer = size + framing * frame;
    final top = lerpDouble(0, bigTop, grow)!;

    return Stack(
      children: [
        Positioned(
          top: small + MiSpace.md,
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: _revealing,
            child: Opacity(
              opacity: 1 - away,
              child: Transform.translate(
                offset: Offset(0, 48 * away),
                child: _questionArea(context),
              ),
            ),
          ),
        ),
        Positioned(
          top: top,
          left: (width - outer) / 2,
          width: outer,
          height: outer,
          child: Semantics(
            image: true,
            label: 'Dein Bild, entsteht aus deinen Antworten',
            excludeSemantics: true,
            child: WerteBildRahmen(
              t: frame,
              child: WerteBild(
                answers: _answers,
                active: _revealing ? null : _step,
                edge: frame < 1 ? colors.keyline : null,
              ),
            ),
          ),
        ),
        if (r > 0)
          Positioned(
            top: bigTop + big + framing + MiSpace.lg,
            left: MiSpace.lg,
            right: MiSpace.lg,
            child: Opacity(
              opacity: titleIn,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - titleIn)),
                child: Column(
                  children: [
                    Text(
                      'Dein Bild',
                      style: text.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: MiSpace.sm),
                    Text(
                      'Aus deinen Antworten. Kein anderes sieht genau so '
                      'aus.',
                      style: text.bodyMedium?.copyWith(
                        color: colors.onTableMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: MiSpace.xs),
                    Text(
                      '${werteBildNummer(_answers)} · ${_date(_revealedAt)}',
                      style: text.labelMedium?.copyWith(
                        color: colors.onTableMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _questionArea(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final reduced = MiMotion.reduced(context);
    final statements = _kStatements[_step];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        MiSpace.base,
        0,
        MiSpace.base,
        MiSpace.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Was passt eher zu dir?',
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MiSpace.xs),
          Text(
            'Kein Richtig oder Falsch. Aus deinen Antworten entsteht dein '
            'Bild.',
            style: text.bodyMedium?.copyWith(color: colors.onTableMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MiSpace.base),
          // Dealt like a card: the answered one is laid aside, tipping as
          // it goes, and the next comes in at a slant from the other side
          // and straightens, both turning round their bottom edge like the
          // hand. Going back runs it the other way.
          AnimatedSwitcher(
            duration: reduced ? Duration.zero : _kDeal,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, if (current != null) current],
            ),
            transitionBuilder: (child, animation) {
              final incoming = child.key == ValueKey(_step);
              final side = (incoming ? 1.0 : -1.0) * (_forward ? 1 : -1);
              return AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, card) {
                  // 1 = lying in place, 0 = off the table.
                  final t = animation.value;
                  final away = 1 - t;
                  return Opacity(
                    opacity:
                        incoming ? (t * 2).clamp(0.0, 1.0) : t.clamp(0.0, 1.0),
                    child: FractionalTranslation(
                      translation: Offset(side * 1.1 * away, 0.05 * away),
                      child: Transform.rotate(
                        alignment: Alignment.bottomCenter,
                        angle: side * away * 9 * math.pi / 180,
                        child: Transform.scale(
                          scale: incoming ? 1 : 1 - 0.06 * away,
                          child: card,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
            child: _QuestionCard(
              key: ValueKey(_step),
              left: statements.$1,
              right: statements.$2,
              face: colors.topics[_step ~/ 2 % colors.topics.length],
              value: _answers[_step],
              onChanged: _answer,
            ),
          ),
          if (_step == 0 && widget.onUseExampleProfile != null) ...[
            const SizedBox(height: MiSpace.sm),
            Center(
              child: TextButton.icon(
                onPressed: widget.onUseExampleProfile,
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Beispiel-Profil übernehmen'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.onTableMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';
}

/// Where the user is in the questionnaire: one dot per question, the
/// current one long, the answered ones full.
class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.step});

  final int count;
  final int step;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Semantics(
      label: 'Frage ${step + 1} von $count',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration:
                  MiMotion.reduced(context) ? Duration.zero : MiMotion.quick,
              margin: const EdgeInsets.only(right: 6),
              width: i == step ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i <= step
                    ? colors.onTable
                    : colors.onTable.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

/// One question as a card: the two statements side by side, in line with
/// the slider below them. Tapping a statement leans towards it.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.left,
    required this.right,
    required this.face,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String left;
  final String right;
  final Color face;
  // Null while unanswered.
  final double? value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final v = value;
    // The statement leaned away from fades back.
    final lean = (v ?? 0) / 2;
    final rule = colors.onCard.withValues(alpha: 0.12);

    Widget statement(String words, double opacity, double towards) => Semantics(
          button: true,
          hint: 'Eher diese Aussage',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(towards),
            child: AnimatedOpacity(
              opacity: opacity,
              duration:
                  MiMotion.reduced(context) ? Duration.zero : MiMotion.quick,
              child: Text(
                words,
                style: text.bodyMedium?.copyWith(
                  color: colors.onCard,
                  fontWeight: FontWeight.w600,
                  height: 1.38,
                ),
              ),
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: colors.cardStock,
        borderRadius: BorderRadius.circular(MiRadius.card),
        border: Border.all(color: colors.keyline),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, MiSpace.base),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: statement(
                      left,
                      lean > 0 ? 1 - 0.55 * lean : 1,
                      -1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MiSpace.md),
                    child: Column(
                      children: [
                        Expanded(child: VerticalDivider(color: rule)),
                        RotatedBox(
                          quarterTurns: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: MiSpace.sm,
                            ),
                            child: Text(
                              'oder',
                              style: text.labelMedium?.copyWith(
                                color: colors.onCardMuted,
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: VerticalDivider(color: rule)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: statement(
                      right,
                      lean < 0 ? 1 + 0.55 * lean : 1,
                      1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: _AnswerBlock(face: face, value: v, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

/// The slider in the axis colour: tap or drag anywhere along the track,
/// with a soft catch in the centre. The words under it say which way the
/// answer leans, so it never rests on position alone.
class _AnswerBlock extends StatefulWidget {
  const _AnswerBlock({
    required this.face,
    required this.value,
    required this.onChanged,
  });

  final Color face;
  final double? value;
  final ValueChanged<double> onChanged;

  @override
  State<_AnswerBlock> createState() => _AnswerBlockState();
}

class _AnswerBlockState extends State<_AnswerBlock> {
  // While the finger is on the marker it follows without easing.
  bool _dragging = false;

  void _pick(double dx, double width) {
    final position =
        ((dx - AxisTrack.markerSize / 2) / (width - AxisTrack.markerSize) * 2 -
                1)
            .clamp(-1.0, 1.0);
    widget.onChanged(position * 2);
  }

  static String? _word(double? v) {
    if (v == null) return null;
    if (v == 0) return 'Beides gleich';
    return v.abs() < 1.3 ? 'Eher das' : 'Genau das';
  }

  String get _reading {
    final v = widget.value;
    if (v == null) return 'Noch nicht beantwortet';
    if (v == 0) return 'Beides gleich';
    final side = v < 0 ? 'die erste Aussage' : 'die zweite Aussage';
    return v.abs() < 1.3 ? 'Eher $side' : 'Genau $side';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final ink = colors.onCard;
    final v = widget.value;
    final word = _word(v);
    final style = text.bodyMedium?.copyWith(
      color: ink,
      fontWeight: FontWeight.w800,
      fontSize: 14,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(
        MiSpace.base,
        MiSpace.xs,
        MiSpace.base,
        MiSpace.md,
      ),
      decoration: BoxDecoration(
        color: widget.face,
        borderRadius: BorderRadius.circular(MiRadius.card - 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            slider: true,
            label: 'Deine Antwort zwischen den beiden Aussagen',
            value: _reading,
            increasedValue: 'weiter zur zweiten Aussage',
            decreasedValue: 'weiter zur ersten Aussage',
            onIncrease: v == null || v < 2
                ? () => widget.onChanged((v ?? 0) + 0.5)
                : null,
            onDecrease: v == null || v > -2
                ? () => widget.onChanged((v ?? 0) - 0.5)
                : null,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  key: const ValueKey('werte-track'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _pick(d.localPosition.dx, width),
                  onHorizontalDragStart: (d) {
                    setState(() => _dragging = true);
                    _pick(d.localPosition.dx, width);
                  },
                  onHorizontalDragUpdate: (d) =>
                      _pick(d.localPosition.dx, width),
                  onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                  onHorizontalDragCancel: () =>
                      setState(() => _dragging = false),
                  child: SizedBox(
                    // A 48dp target around the 28dp track.
                    height: 48,
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: (v ?? 0) / 2),
                        duration: _dragging || MiMotion.reduced(context)
                            ? Duration.zero
                            : MiMotion.settle,
                        curve: MiMotion.ease,
                        builder: (context, t, _) => AxisTrack(
                          position: t,
                          ink: ink,
                          stock: colors.cardStock,
                          marker: v != null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (word == null)
                    Flexible(
                      child: Text(
                        'Zieh oder tippe auf eine Seite',
                        style: style?.copyWith(
                          color: ink.withValues(alpha: 0.75),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else ...[
                    if (v! < 0) ...[
                      Icon(Icons.arrow_back_rounded, size: 18, color: ink),
                      const SizedBox(width: MiSpace.xs),
                    ],
                    Flexible(child: Text(word, style: style)),
                    if (v > 0) ...[
                      const SizedBox(width: MiSpace.xs),
                      Icon(Icons.arrow_forward_rounded, size: 18, color: ink),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
