import 'package:flutter/material.dart';

import '../../app/theme/mi_theme.dart';
import 'notifications.dart';

/// After the first action: what notifications bring, then Android's own
/// question on "Ja, gerne". "Später" leaves Android's question unasked, so
/// the first star can still bring it up.
Future<void> askForNotifications(BuildContext context) async {
  final notifications = Notifications.current;
  if (!notifications.available || await notifications.allowed()) return;
  if (!context.mounted) return;
  final theme = Theme.of(context);
  final yes = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.mi.table,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Theme(data: theme, child: const NotificationAskSheet()),
  );
  if (yes ?? false) await notifications.requestPermission();
}

class NotificationAskSheet extends StatelessWidget {
  const NotificationAskSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          MiSpace.lg,
          0,
          MiSpace.lg,
          MiSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 40,
              color: colors.onTable,
            ),
            const SizedBox(height: MiSpace.md),
            Text(
              'Was wird daraus?',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: MiSpace.sm),
            Text(
              'Wir sagen dir Bescheid, wenn es Neues gibt, und erinnern dich '
              'montags an neue Möglichkeiten zum Mitreden.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onTableMuted,
              ),
            ),
            const SizedBox(height: MiSpace.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: colors.tableButton,
              child: const Text('Ja, gerne'),
            ),
            const SizedBox(height: MiSpace.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Später'),
            ),
          ],
        ),
      ),
    );
  }
}

/// After a star was set or taken away: a short hint, no question. A star
/// means "tell me what's new", so the first one brings up Android's own
/// permission question, which the app can't skip.
Future<void> showStarHint(BuildContext context, {required bool starred}) async {
  final notifications = Notifications.current;
  if (!notifications.available) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!starred) {
    notifications.refresh();
    _show(messenger, 'Keine Neuigkeiten mehr dazu.');
    return;
  }
  final allowed =
      await notifications.allowed() || await notifications.requestPermission();
  if (allowed) {
    notifications.refresh();
    _show(
      messenger,
      'Du bekommst ab jetzt alle Neuigkeiten dazu. Ein Tipp auf den Stern '
      'beendet das.',
    );
  } else {
    _show(
      messenger,
      'Benachrichtigungen sind für MeinImpact aus.',
      action: SnackBarAction(
        label: 'Einschalten',
        onPressed: notifications.openSettings,
      ),
    );
  }
}

void _show(
  ScaffoldMessengerState messenger,
  String text, {
  SnackBarAction? action,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
}
