import 'package:flutter/material.dart';

import '../../app/theme/mi_theme.dart';
import '../../core/feedback/beta_feedback.dart';

/// What the user said in the reason sheet. The sheet resolves to null when
/// it was skipped or swiped away: the card stays thrown away, no reason.
class CardVerdict {
  const CardVerdict.keep()
      : keep = true,
        reason = null,
        note = null;

  const CardVerdict.because(CardReason this.reason, {this.note}) : keep = false;

  // "Doch behalten": the card goes back into the hand.
  final bool keep;
  final CardReason? reason;
  final String? note;
}

/// After a card was thrown away: one tap on a reason sends it. The two
/// reasons that invite a few words open a field first.
Future<CardVerdict?> showCardReasonSheet(BuildContext context) {
  return _showSheet<CardVerdict>(context, const _ReasonSheet());
}

/// "Feedback geben": resolves to true once the message is sent.
Future<bool> showFeedbackSheet(
  BuildContext context, {
  required String screen,
}) async {
  final sent = await _showSheet<bool>(context, _MessageSheet(screen: screen));
  return sent ?? false;
}

/// A sheet on the card table that grows with its content and moves up with
/// the keyboard. Routes do not inherit the tab's theme, so it is handed on,
/// or the table's own when the caller sits outside it.
Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  final current = Theme.of(context);
  final theme = current.extension<MiColors>() != null
      ? current
      : miTheme(MediaQuery.platformBrightnessOf(context));
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: theme.extension<MiColors>()!.table,
    builder: (context) => Theme(
      data: theme,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MiSpace.lg,
            0,
            MiSpace.lg,
            MiSpace.lg,
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet();

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  // A reason that takes a note, picked and waiting for "Senden".
  CardReason? _open;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _pick(CardReason reason) {
    if (reason.takesNote) {
      setState(() => _open = _open == reason ? null : reason);
      return;
    }
    Navigator.of(context).pop(CardVerdict.because(reason));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final open = _open;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Warum legst du sie weg?', style: text.titleLarge),
        const SizedBox(height: MiSpace.base),
        Wrap(
          spacing: MiSpace.sm,
          runSpacing: MiSpace.sm,
          children: [
            for (final reason in CardReason.values)
              _Pill(
                label: reason.label,
                selected: reason == open,
                onPressed: () => _pick(reason),
              ),
          ],
        ),
        if (open != null) ...[
          const SizedBox(height: MiSpace.base),
          _NoteField(
            controller: _note,
            hint: open == CardReason.dontSupport
                ? 'Warum nicht? Wenn du magst.'
                : 'Was passt nicht? Wenn du magst.',
            maxLength: 500,
          ),
          const SizedBox(height: MiSpace.md),
          FilledButton(
            style: colors.tableButton,
            onPressed: () => Navigator.of(context).pop(
              CardVerdict.because(open, note: _note.text),
            ),
            child: const Text('Senden'),
          ),
        ],
        const SizedBox(height: MiSpace.sm),
        Row(
          children: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: colors.onTable),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Überspringen'),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: colors.onTable),
              onPressed: () =>
                  Navigator.of(context).pop(const CardVerdict.keep()),
              child: const Text('Doch behalten'),
            ),
          ],
        ),
      ],
    );
  }
}

class _MessageSheet extends StatefulWidget {
  const _MessageSheet({required this.screen});

  final String screen;

  @override
  State<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends State<_MessageSheet> {
  MessageKind? _kind;
  final _message = TextEditingController();
  bool _sending = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send(MessageKind kind) async {
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      await BetaFeedback.current.message(
        kind: kind,
        message: _message.text,
        screen: widget.screen,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    final kind = _kind;
    final ready = kind != null && _message.text.trim().isNotEmpty && !_sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Feedback geben', style: text.titleLarge),
        const SizedBox(height: MiSpace.base),
        Wrap(
          spacing: MiSpace.sm,
          runSpacing: MiSpace.sm,
          children: [
            for (final k in MessageKind.values)
              _Pill(
                label: k.label,
                selected: k == kind,
                onPressed: () => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: MiSpace.base),
        _NoteField(
          controller: _message,
          hint: switch (kind) {
            MessageKind.bug => 'Was ist passiert, und wo?',
            MessageKind.idea => 'Was wäre besser?',
            MessageKind.praise => 'Was gefällt dir?',
            _ => 'Was möchtest du uns sagen?',
          },
          maxLength: 2000,
          minLines: 5,
        ),
        if (_failed) ...[
          const SizedBox(height: MiSpace.sm),
          Text(
            'Das ging gerade nicht raus. Prüf deine Verbindung und versuch '
            'es noch einmal.',
            style: text.bodyMedium?.copyWith(color: colors.onTable),
          ),
        ],
        const SizedBox(height: MiSpace.md),
        FilledButton(
          style: colors.tableButton,
          onPressed: ready ? () => _send(kind) : null,
          child: Text(_sending ? 'Wird gesendet …' : 'Senden'),
        ),
      ],
    );
  }
}

/// A choice on the table: outlined, filled once picked.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: selected ? colors.table : colors.onTable,
          // Filled, not outlined: a soft tint until picked, then inverted.
          backgroundColor: selected
              ? colors.onTable
              : colors.onTable.withValues(alpha: 0.07),
          side: BorderSide.none,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: MiSpace.base),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: MiFonts.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.hint,
    required this.maxLength,
    this.minLines = 3,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(MiRadius.tile),
      borderSide: BorderSide(color: colors.onTableMuted),
    );
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: minLines + 3,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: colors.onTable),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.onTableMuted),
        filled: true,
        fillColor: colors.tableRaised,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.onTable, width: 1.5),
        ),
        // No counter: the limit is generous and only stops runaway text.
        counterText: '',
      ),
    );
  }
}
