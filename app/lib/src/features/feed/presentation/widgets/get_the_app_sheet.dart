import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/mi_theme.dart';

// Where the web teaser sends people to get the app. Set per build via
// --dart-define=MEINIMPACT_APP_DOWNLOAD_URL=... once store links exist.
const _kDownloadUrl = String.fromEnvironment(
  'MEINIMPACT_APP_DOWNLOAD_URL',
  defaultValue: 'https://meinimpact.de/#beta',
);

/// Web only. The web build is a teaser (decided 2026-11-09): people can look
/// around, but taking part happens in the Android/iOS app, where the
/// in-app browser, the letter and "Fertig" work without workarounds.
class GetTheAppSheet extends StatelessWidget {
  const GetTheAppSheet({super.key});

  // The sheet is a new route: it takes the theme of the table it opens on.
  static Future<void> show(BuildContext context) {
    final theme = Theme.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.mi.table,
      showDragHandle: true,
      // Taller than the default 9/16 when the text needs it (small phones)
      isScrollControlled: true,
      builder: (_) => Theme(data: theme, child: const GetTheAppSheet()),
    );
  }

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
            Icon(Icons.phone_iphone, size: 40, color: colors.onTable),
            const SizedBox(height: MiSpace.md),
            Text(
              'Mitmachen geht in der App',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: MiSpace.sm),
            Text(
              'In der MeinImpact-App unterschreibst du Petitionen, machst bei '
              'Umfragen mit und schreibst dem Stadtrat, ohne die App zu '
              'verlassen. Für Android, bald auch fürs iPhone.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onTableMuted,
              ),
            ),
            const SizedBox(height: MiSpace.lg),
            FilledButton(
              onPressed: () => launchUrl(Uri.parse(_kDownloadUrl)),
              style: colors.tableButton,
              child: const Text('App holen'),
            ),
            const SizedBox(height: MiSpace.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Weiter umsehen'),
            ),
          ],
        ),
      ),
    );
  }
}
