import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The fixed bottom bar with "Fertig" on the right. A bar rather than a
/// floating button, so it never covers a site's own submit button.
class DoneBar extends StatelessWidget {
  const DoneBar({required this.hint, required this.onDone, super.key});

  final String hint;
  // Null disables the button.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hint,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedText,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onDone,
                icon: const Icon(Icons.check),
                label: const Text('Fertig'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
