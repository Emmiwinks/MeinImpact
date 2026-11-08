import 'package:flutter/material.dart';

import '../../domain/opportunity.dart';
import 'app_colors.dart';

/// Shown right after "Fertig". Pops with true when the user taps
/// "Rückgängig".
class ActionDoneSheet extends StatelessWidget {
  const ActionDoneSheet({required this.opportunity, super.key});

  final Opportunity opportunity;

  /// Shows the sheet; true when the user undid the action.
  static Future<bool> show(
    BuildContext context,
    Opportunity opportunity,
  ) async {
    final undone = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => ActionDoneSheet(opportunity: opportunity),
    );
    return undone ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              'Stark, erledigt!',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              opportunity.title,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.mutedText,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Rückgängig'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Weiter'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
