import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_colors.dart';

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

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        // Taller than the default 9/16 when the text needs it (small phones)
        isScrollControlled: true,
        builder: (_) => const GetTheAppSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_iphone, size: 40, color: AppColors.green),
              const SizedBox(height: 12),
              Text(
                'Mitmachen geht in der App',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'In der MeinImpact-App unterschreibst du Petitionen, machst bei '
                'Umfragen mit und schreibst dem Stadtrat, ohne die App zu '
                'verlassen. Für Android, bald auch fürs iPhone.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => launchUrl(Uri.parse(_kDownloadUrl)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text('App holen'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Weiter umsehen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
