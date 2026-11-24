import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/mi_theme.dart';

/// The full privacy policy, on the website (Google Play also expects it in
/// the app; the profile links it too).
final kPrivacyPolicyUrl = Uri.parse('https://meinimpact.de/datenschutz.html');

/// The consent, after the intro and before any data is entered; putting
/// the questionnaire off ("Lieber später") passes through it too. The key facts stand on the screen
/// itself (explicit consent needs them visible), the full policy is one
/// tap away, and "Einverstanden" waits for the age confirmation.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({required this.onAgree, this.onBack, super.key});

  final VoidCallback onAgree;

  /// System Back: to the intro. Null lets the route pop.
  final VoidCallback? onBack;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _sixteen = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return PopScope(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack?.call();
      },
      child: Scaffold(
        backgroundColor: colors.table,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    MiSpace.lg,
                    MiSpace.xl + MiSpace.sm,
                    MiSpace.lg,
                    MiSpace.base,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Kurz zu deinen Daten',
                          style: text.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: MiSpace.lg),
                      const _Fact(
                        icon: Icons.smartphone_rounded,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Deine Werte, deine Lebenslage und deine '
                                  'Prioritäten',
                              style: bold,
                            ),
                            TextSpan(text: ' bleiben auf deinem Handy.'),
                          ],
                        ),
                      ),
                      const _Fact(
                        icon: Icons.forward_to_inbox_rounded,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Für einen Brief geht dein Text kurz an '
                                  'eine KI in der EU, die ihn entwirft. ',
                            ),
                            TextSpan(
                              text: 'Wir speichern ihn nicht.',
                              style: bold,
                            ),
                          ],
                        ),
                      ),
                      const _Fact(
                        icon: Icons.chat_bubble_outline_rounded,
                        text: TextSpan(
                          text: 'Wenn du uns Feedback gibst, etwa warum du '
                              'eine Karte weglegst, speichern wir es unter '
                              'einem Codenamen und löschen es nach '
                              '180 Tagen.',
                        ),
                      ),
                      const SizedBox(height: MiSpace.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: () => launchUrl(
                            kPrivacyPolicyUrl,
                            mode: LaunchMode.inAppBrowserView,
                          ),
                          borderRadius: BorderRadius.circular(MiRadius.tile),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Und hier das rechtssichere Bla-bla zum '
                                    'Gegenlesen',
                                    style: text.labelLarge?.copyWith(
                                      fontSize: 15,
                                      height: 1.3,
                                      decoration: TextDecoration.underline,
                                      decorationColor: colors.onTable,
                                      decorationThickness: 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: MiSpace.sm),
                                Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                  color: colors.onTable,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MiSpace.sm,
                  MiSpace.sm,
                  MiSpace.lg,
                  MiSpace.base,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MergeSemantics(
                      child: InkWell(
                        onTap: () => setState(() => _sixteen = !_sixteen),
                        borderRadius: BorderRadius.circular(MiRadius.tile),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _sixteen,
                                onChanged: (v) =>
                                    setState(() => _sixteen = v ?? false),
                              ),
                              const SizedBox(width: MiSpace.xs),
                              Expanded(
                                child: Text(
                                  'Ich bin mindestens 16 Jahre alt.',
                                  style: text.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: MiSpace.sm),
                    Padding(
                      padding: const EdgeInsets.only(left: MiSpace.base),
                      child: FilledButton(
                        onPressed: _sixteen ? widget.onAgree : null,
                        style: colors.tableButton,
                        child: const Text('Einverstanden'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One key fact, with its glyph on a small raised tile.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final TextSpan text;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    return Padding(
      padding: const EdgeInsets.only(bottom: MiSpace.base + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.onTable.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(MiRadius.tile),
              ),
              child: Icon(icon, size: 26, color: colors.onTable),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text.rich(
                text,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
