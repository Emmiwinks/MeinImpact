import 'package:flutter/material.dart';

import 'notifications.dart';

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
