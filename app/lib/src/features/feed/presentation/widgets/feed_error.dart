import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import 'app_colors.dart';
import 'shared_widgets.dart';

class FeedError extends StatelessWidget {
  const FeedError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SurfaceCard(
      child: Text(
        l10n.recommendationsLoadError(message),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.ink,
            ),
      ),
    );
  }
}
