import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Like `find.text`, but also finds an AI-written text with the AI mark
/// after it (`AiText`): the mark is a placeholder in the span, so the plain
/// text no longer equals the words alone.
Finder findText(String text) => find.byWidgetPredicate(
      (widget) => switch (widget) {
        Text(data: final data?) => data == text,
        Text(textSpan: final span?) =>
          span.toPlainText(
                includeSemanticsLabels: false,
                includePlaceholders: false,
              ) ==
              text,
        EditableText(:final controller) => controller.text == text,
        _ => false,
      },
      description: 'text "$text"',
    );
