import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';

import '../domain/letter_recipients.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_repository.dart';
import 'widgets/app_colors.dart';
import 'widgets/done_bar.dart';

/// The letter to the members of a body about to vote on a council decision:
/// the user's notes for the AI, the drafted letter (editable), then their
/// own mail app. Pops with true when the user taps "Fertig" (or iOS reports
/// the mail as sent). MeinImpact never sends anything itself.
class LetterScreen extends StatefulWidget {
  const LetterScreen({
    required this.opportunity,
    required this.repository,
    required this.onViewPaper,
    this.sendMail = FlutterEmailSender.send,
    super.key,
  });

  final Opportunity opportunity;
  final OpportunityRepository repository;
  // Opens the Ratsvorlage itself (in-app browser or new tab).
  final VoidCallback onViewPaper;
  // The platform mail composer; replaceable in tests.
  final Future<EmailSendResult> Function(Email email) sendMail;

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
  LetterRecipients? _recipients;
  var _recipientsLoading = true;
  // Selected office addresses; all known ones start selected.
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _loadRecipients();
  }

  Future<void> _loadRecipients() async {
    try {
      final recipients = await widget.repository.letterRecipients(
        widget.opportunity.id,
      );
      if (!mounted) return;
      setState(() {
        _recipients = recipients;
        _selected.addAll(recipients.offices.map((o) => o.email).nonNulls);
      });
    } catch (error) {
      // Without recipients the user fills in "An" in the mail app.
      debugPrint('Letter recipients failed: $error');
    } finally {
      if (mounted) setState(() => _recipientsLoading = false);
    }
  }

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

  // The platform composer: inside the app on iOS (Apple Mail account), an
  // email app on Android that hands back to us after sending, `mailto:`
  // elsewhere. Only iOS reports a sent mail; that counts as "Fertig".
  Future<void> _openMailApp() async {
    final EmailSendResult result;
    try {
      result = await widget.sendMail(
        Email(subject: _subject, body: _letter.text.trim(), recipients: _to),
      );
    } on FlutterEmailSenderNotAvailableException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keine Mail-App gefunden. Kopiere Brief und Adressen in dein '
            'Webmail.',
          ),
        ),
      );
      return;
    }
    if (result == EmailSendResult.sent && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  // Selected addresses in the offices' (alphabetical) order, all openly in
  // "An".
  List<String> get _to => [
        for (final office in _recipients?.offices ?? const <FraktionOffice>[])
          if (_selected.contains(office.email)) office.email!,
      ];

  // For webmail or when no mail app is set up.
  Future<void> _copyAddresses() async {
    await Clipboard.setData(ClipboardData(text: _to.join(', ')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adressen kopiert')),
    );
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
                ? '$body, Sitzung am '
                    '${meeting.day}.${meeting.month}.${meeting.year}'
                : body,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
          ),
          TextButton.icon(
            onPressed: widget.onViewPaper,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Vorlage ansehen'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
          ),
          _RecipientsSection(
            loading: _recipientsLoading,
            recipients: _recipients,
            selected: _selected,
            onToggle: (email) => setState(
              () => _selected.contains(email)
                  ? _selected.remove(email)
                  : _selected.add(email),
            ),
          ),
          const SizedBox(height: 16),
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
              _selected.isEmpty
                  ? 'Unterschreibe mit deinem Namen, bevor du ihn abschickst. '
                      'Die Empfänger:innen trägst du in deiner Mail-App ein.'
                  : 'Unterschreibe mit deinem Namen, bevor du ihn abschickst. '
                      'Die Mail-App öffnet sich mit den ausgewählten '
                      'Fraktionsbüros in „An“.',
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
            if (_selected.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _copyAddresses,
                  icon: const Icon(Icons.alternate_email, size: 18),
                  label: const Text('Adressen kopieren (für Webmail)'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
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

/// "An": the Fraktion offices (all known addresses pre-selected), and the
/// members of the bodies behind them. District and village councils come
/// with names only for now.
class _RecipientsSection extends StatelessWidget {
  const _RecipientsSection({
    required this.loading,
    required this.recipients,
    required this.selected,
    required this.onToggle,
  });

  final bool loading;
  final LetterRecipients? recipients;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: AppColors.mutedText);
    final recipients = this.recipients;
    final offices = recipients?.offices ?? const <FraktionOffice>[];
    final members = recipients?.members ?? const <CouncilMember>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'AN',
          style: textTheme.labelSmall?.copyWith(
            color: AppColors.mutedText,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        if (loading)
          const LinearProgressIndicator(minHeight: 2)
        else if (offices.isNotEmpty) ...[
          Text(
            'Die Büros der Fraktionen geben deine Nachricht an ihre '
            'Mitglieder weiter.',
            style: muted,
          ),
          for (final office in offices)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: office.email != null && selected.contains(office.email),
              onChanged:
                  office.email == null ? null : (_) => onToggle(office.email!),
              title: Text(office.fraktion),
              subtitle: Text(office.email ?? 'Adresse fehlt noch'),
            ),
        ] else
          Text(
            members.isNotEmpty
                ? 'Für Stadtbezirksbeiräte und Ortschaftsräte haben wir noch '
                    'keine Adressen. Trag die Empfänger:innen in deiner '
                    'Mail-App ein.'
                : 'Trag die Empfänger:innen in deiner Mail-App ein.',
            style: muted,
          ),
        if (!loading && members.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(
              'Mitglieder: ${recipients!.bodies.join(', ')} '
              '(${members.length})',
              style: textTheme.bodyMedium,
            ),
            children: [
              for (final member in members)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      member.fraktion != null
                          ? '${member.name} · ${member.fraktion}'
                          : member.name,
                      style: textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
