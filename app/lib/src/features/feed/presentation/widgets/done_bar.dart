import 'package:flutter/material.dart';

import '../../../../app/theme/mi_theme.dart';

/// The fixed bottom bar with "Fertig" on the right. A bar rather than a
/// floating button, so it never covers a site's own submit button. Flat on
/// the table, a keyline above.
class DoneBar extends StatelessWidget {
  const DoneBar({required this.hint, required this.onDone, super.key});

  final String hint;
  // Null disables the button.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.table,
        border: Border(top: BorderSide(color: colors.keyline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MiSpace.lg,
            MiSpace.md,
            MiSpace.base,
            MiSpace.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hint,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onTableMuted,
                      ),
                ),
              ),
              const SizedBox(width: MiSpace.md),
              FilledButton.icon(
                onPressed: onDone,
                icon: const Icon(Icons.check),
                label: const Text('Fertig'),
                style: colors.tableButton.copyWith(
                  minimumSize: const WidgetStatePropertyAll(Size(120, 52)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
