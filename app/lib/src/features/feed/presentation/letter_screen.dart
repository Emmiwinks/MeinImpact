import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/opportunity.dart';
import '../domain/opportunity_repository.dart';
import 'widgets/app_colors.dart';
import 'widgets/done_bar.dart';

/// The letter to the members of a body about to vote on a council decision:
/// the user's notes for the AI, the drafted letter (editable), then their
/// own mail app. Pops with true when the user taps "Fertig". MeinImpact
/// never sends anything itself.
class LetterScreen extends StatefulWidget {
  const LetterScreen({
    required this.opportunity,
    required this.repository,
    required this.onViewPaper,
    super.key,
  });

  final Opportunity opportunity;
  final OpportunityRepository repository;
  // Opens the Ratsvorlage itself (in-app browser or new tab).
  final VoidCallback onViewPaper;

  /// Opens the letter for [opportunity]; true when the user marked it done.
  static Future<bool> open(
    BuildContext context,
    Opportunity opportunity, {
    required OpportunityRepository repository,
    required VoidCallback onViewPaper,
  }) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LetterScreen(
          opportunity: opportunity,
          repository: repository,
          onViewPaper: onViewPaper,
        ),
      ),
    );
    return done ?? false;
  }

  @override
  State<LetterScreen> createState() => _LetterScreenState();
}

enum _DraftState { idle, streaming, done, failed }

class _LetterScreenState extends State<LetterScreen> {
  final _notes = TextEditingController();
  final _letter = TextEditingController();
  var _state = _DraftState.idle;

  @override
  void dispose() {
    _notes.dispose();
    _letter.dispose();
    super.dispose();
  }

  Future<void> _draft() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _state = _DraftState.streaming;
      _letter.clear();
    });
    try {
      await for (final chunk in widget.repository.streamLetter(
        widget.opportunity.id,
        notes: _notes.text,
      )) {
        if (!mounted) return;
        _letter.text += chunk;
      }
      if (mounted) setState(() => _state = _DraftState.done);
    } catch (error) {
      debugPrint('Letter draft failed: $error');
      // The letter can still be written by hand in the same field.
      if (mounted) setState(() => _state = _DraftState.failed);
    }
  }

  String get _subject => 'Ratsvorlage: ${widget.opportunity.title}';

  Future<void> _openMailApp() async {
    // Built by hand: Uri.queryParameters encodes spaces as "+", which mail
    // apps show literally.
    final query = 'subject=${Uri.encodeComponent(_subject)}'
        '&body=${Uri.encodeComponent(_letter.text.trim())}';
    await launchUrl(Uri.parse('mailto:?$query'));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _letter.text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Brief kopiert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opportunity = widget.opportunity;
    final textTheme = Theme.of(context).textTheme;
    final body = opportunity.organizer ?? 'Stadtrat';
    final meeting = opportunity.closesOn;
    final streaming = _state == _DraftState.streaming;
    final hasLetter = _letter.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Schließen',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Brief schreiben'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          Text(
            opportunity.title,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            meeting != null
                ? 'An die Mitglieder: $body, '
                    'Sitzung am ${meeting.day}.${meeting.month}.${meeting.year}'
                : 'An die Mitglieder: $body',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
          TextButton.icon(
            onPressed: widget.onViewPaper,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Vorlage ansehen'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            enabled: !streaming,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Was ist dir wichtig? (optional)',
              hintText: 'Deine Haltung, wie es dich betrifft, was du dir '
                  'wünschst. Die KI baut das in den Brief ein.',
              hintMaxLines: 3,
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: streaming ? null : _draft,
            icon: streaming
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _state == _DraftState.idle ? 'Brief erstellen' : 'Neu erstellen',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (_state != _DraftState.idle) ...[
            const SizedBox(height: 16),
            if (_state == _DraftState.failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Der Entwurf konnte gerade nicht erstellt werden. Du kannst '
                  'es gleich noch einmal versuchen oder selbst schreiben.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            TextField(
              controller: _letter,
              readOnly: streaming,
              minLines: 8,
              maxLines: null,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Dein Brief (bearbeitbar)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Unterschreibe mit deinem Namen, bevor du ihn abschickst. '
              'Die Empfänger:innen trägst du in deiner Mail-App ein.',
              style: textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasLetter && !streaming ? _copy : null,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Kopieren'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasLetter && !streaming ? _openMailApp : null,
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: const Text('Mail-App'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: _state == _DraftState.idle
          ? null
          : DoneBar(
              hint: 'Abgeschickt? Dann tippe auf Fertig.',
              onDone: streaming ? null : () => Navigator.of(context).pop(true),
            ),
    );
  }
}
