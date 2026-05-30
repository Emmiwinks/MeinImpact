import 'package:flutter/material.dart';
import 'package:meinimpact/l10n/app_localizations.dart';

import 'app_colors.dart';

class AppFrame extends StatelessWidget {
  const AppFrame({
    required this.l10n,
    required this.selectedLocale,
    required this.onLocaleChanged,
    required this.child,
    super.key,
  });

  final AppLocalizations l10n;
  final Locale selectedLocale;
  final ValueChanged<Locale> onLocaleChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 860;
          final horizontalPadding = isWide ? 32.0 : 18.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      l10n: l10n,
                      selectedLocale: selectedLocale,
                      onLocaleChanged: onLocaleChanged,
                    ),
                    const SizedBox(height: 22),
                    child,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.l10n,
    required this.selectedLocale,
    required this.onLocaleChanged,
  });

  final AppLocalizations l10n;
  final Locale selectedLocale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.brandName,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: AppColors.green,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.appTagline,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.mutedText,
              ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 14),
              _LanguageMenu(
                selectedLocale: selectedLocale,
                onLocaleChanged: onLocaleChanged,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            _LanguageMenu(
              selectedLocale: selectedLocale,
              onLocaleChanged: onLocaleChanged,
            ),
          ],
        );
      },
    );
  }
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({
    required this.selectedLocale,
    required this.onLocaleChanged,
  });

  final Locale selectedLocale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.languageMenuLabel,
      button: true,
      child: Container(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Locale>(
            key: const Key('languageSelector'),
            value: selectedLocale,
            borderRadius: BorderRadius.circular(16),
            icon: const Icon(Icons.expand_more_rounded),
            onChanged: (locale) {
              if (locale != null) {
                onLocaleChanged(locale);
              }
            },
            items: [
              DropdownMenuItem(
                value: const Locale('de'),
                child: Text(l10n.languageGerman),
              ),
              DropdownMenuItem(
                value: const Locale('en'),
                child: Text(l10n.languageEnglish),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
