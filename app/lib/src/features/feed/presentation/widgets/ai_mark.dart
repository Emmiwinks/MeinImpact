import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The EU icon for AI-generated content (EU AI Act Art. 50(4), Code of
/// Practice Measure 1.1) on every text the enrichment wrote: the official
/// basic icon, black on light grounds, white on dark ones. Screen readers
/// hear it in German.
class AiMark extends StatelessWidget {
  const AiMark({required this.onDark, super.key});

  final bool onDark;

  static const semanticLabel = 'KI-generierter Text';

  static const _size = 17.0;

  /// How wide the mark is drawn, for fitting a title around it.
  static double widthOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_size);

  @override
  Widget build(BuildContext context) {
    final size = widthOf(context);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SvgPicture.asset(
        onDark ? 'assets/ai/ai_white.svg' : 'assets/ai/ai_black.svg',
        width: size,
        height: size,
      ),
    );
  }
}

/// [text] in [style] with the [AiMark] right after its last word, so the
/// mark labels the text itself and follows it wherever the line breaks.
class AiText extends StatelessWidget {
  const AiText(
    this.text, {
    required this.style,
    required this.onDark,
    this.maxLines,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final bool onDark;
  final int? maxLines;

  static const gap = 6.0;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: gap),
              child: AiMark(onDark: onDark),
            ),
          ),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
