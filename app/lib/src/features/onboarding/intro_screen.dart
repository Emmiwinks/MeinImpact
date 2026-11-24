import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/mi_theme.dart';
import '../feed/presentation/widgets/werte_bild.dart';
import 'rucksack/rucksack_bag.dart';
import 'stadthaushalt/stadthaushalt.dart';

/// The first screen: what the questionnaire is for and its three parts,
/// each with a small preview of the real thing (a half-painted Wertebild,
/// the open Rucksack, three Taler). No privacy line here: the next screen
/// is the consent, and each step says it where data is entered.
class IntroScreen extends StatelessWidget {
  const IntroScreen({
    required this.onStart,
    required this.onLater,
    super.key,
  });

  final VoidCallback onStart;

  /// "Lieber später": skips the questions, the actions come at random.
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.table,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  MiSpace.lg,
                  MiSpace.lg,
                  MiSpace.lg,
                  MiSpace.base,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Fan(),
                    const SizedBox(height: 26),
                    // One voice, one size (user decision): no heading with
                    // a smaller line under it.
                    Text(
                      'Möchtest du genau die Aktionen sehen, die zu dir '
                      'passen? Dann fülle jetzt unseren kleinen Fragebogen '
                      'aus.',
                      style: text.bodyLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: MiSpace.lg),
                    const _Item(
                      preview: _HalfPicture(),
                      title: 'Deine Werte',
                      line: '8 kurze Fragen, was dir politisch wichtig ist',
                      first: true,
                    ),
                    const _Item(
                      preview: _OpenBag(),
                      title: 'Deine Lebenslage',
                      line: 'Wo du wohnst und was dein Leben ausmacht',
                    ),
                    const _Item(
                      preview: TalerHaeufchen(),
                      title: 'Deine Prioritäten',
                      line: 'Wofür deine Stadt Geld ausgeben soll',
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MiSpace.lg,
                MiSpace.sm,
                MiSpace.lg,
                MiSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: onStart,
                    style: colors.tableButton,
                    child: const Text("Los geht's · ca. 5 Minuten"),
                  ),
                  const SizedBox(height: MiSpace.xs),
                  TextButton(
                    onPressed: onLater,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Lieber später?\n',
                            style: TextStyle(
                              color: colors.onTableMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const TextSpan(
                            text: 'Erst mal nur Aktionen ansehen.',
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three face-down cards, fanned: the actions the questions pick.
class _Fan extends StatelessWidget {
  const _Fan();

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    Widget card(double left, double degrees, Color color) => Positioned(
          left: left,
          bottom: 0,
          child: Transform.rotate(
            angle: degrees * math.pi / 180,
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 70,
              height: 100,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.cardStock, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
        );
    return ExcludeSemantics(
      child: SizedBox(
        height: 112,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            card(4, -14, colors.topics[3]),
            card(44, -4, colors.topics[1]),
            card(86, 7, colors.topics[0]),
          ],
        ),
      ),
    );
  }
}

/// One of the three parts: its preview on a small sheet of card stock,
/// then what it is in plain words.
class _Item extends StatelessWidget {
  const _Item({
    required this.preview,
    required this.title,
    required this.line,
    this.first = false,
  });

  final Widget preview;
  final String title;
  final String line;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final keyline = BorderSide(color: colors.keyline);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: first ? keyline : BorderSide.none, bottom: keyline),
      ),
      child: MergeSemantics(
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1EA),
                  borderRadius: BorderRadius.circular(MiRadius.tile),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: preview,
                ),
              ),
            ),
            const SizedBox(width: MiSpace.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    line,
                    style:
                        text.bodyMedium?.copyWith(color: colors.onTableMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Wertebild halfway: two shapes painted, two still dashed outlines.
class _HalfPicture extends StatelessWidget {
  const _HalfPicture();

  @override
  Widget build(BuildContext context) => const WerteBild(
        answers: [-1.2, 0.6, 1.4, 0.9, null, null, null, null],
      );
}

/// The Rucksack, open, with two tags in it.
class _OpenBag extends StatelessWidget {
  const _OpenBag();

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Center(
      child: RucksackBag(
        width: 54,
        items: [
          PackedItem(
            id: 'a',
            color: colors.topics[0],
            slot: 0,
            isPrivate: false,
          ),
          PackedItem(
            id: 'b',
            color: colors.topics[1],
            slot: 1,
            isPrivate: false,
          ),
        ],
      ),
    );
  }
}
