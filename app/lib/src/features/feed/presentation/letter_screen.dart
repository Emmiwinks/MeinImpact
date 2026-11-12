import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';

import '../../../app/theme/mi_theme.dart';
import '../domain/letter_recipients.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_repository.dart';
import 'hand/topic_art.dart';
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
    final colors = context.mi;
    final opportunity = widget.opportunity;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodyMedium?.copyWith(color: colors.onTableMuted);
    final body = opportunity.organizer ?? 'Stadtrat';
    final meeting = opportunity.closesOn;
    final streaming = _state == _DraftState.streaming;
    final hasLetter = _letter.text.trim().isNotEmpty;
    final drafted = _state != _DraftState.idle;
    final draftLabel = Text(drafted ? 'Neu erstellen' : 'Brief erstellen');
    final draftIcon = streaming
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.onTableMuted,
            ),
          )
        : const Icon(Icons.auto_awesome, size: 18);

    return Scaffold(
      backgroundColor: colors.table,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Schließen',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Brief schreiben'),
      ),
      // A short form: built in one go rather than lazily.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          MiSpace.lg,
          MiSpace.sm,
          MiSpace.lg,
          MiSpace.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The decision, laid out like a row in "Alle Aktionen".
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardThumbnail(look: TopicLook.of(opportunity)),
                const SizedBox(width: MiSpace.base),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(opportunity.title, style: textTheme.titleMedium),
                      const SizedBox(height: MiSpace.xs),
                      Text(
                        meeting != null
                            ? '$body, Sitzung am '
                                '${meeting.day}.${meeting.month}.${meeting.year}'
                            : body,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onTableMuted,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: widget.onViewPaper,
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('Vorlage ansehen'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _Divider(color: colors.keyline),
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
            _Divider(color: colors.keyline),
            Text('Was ist dir wichtig?', style: textTheme.titleMedium),
            const SizedBox(height: MiSpace.xs),
            Text(
              'Optional. Deine Haltung, wie es dich betrifft, was du dir '
              'wünschst. Die KI baut das in den Brief ein.',
              style: muted,
            ),
            const SizedBox(height: MiSpace.md),
            TextField(
              controller: _notes,
              enabled: !streaming,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              style: textTheme.bodyLarge,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Ich fahre dort jeden Tag mit dem Rad …',
              ),
            ),
            const SizedBox(height: MiSpace.sm),
            // Once there is a letter, sending it is the main step; drafting
            // again steps back to an outline.
            if (drafted)
              OutlinedButton.icon(
                onPressed: streaming ? null : _draft,
                icon: draftIcon,
                label: draftLabel,
              )
            else
              FilledButton.icon(
                onPressed: _draft,
                icon: draftIcon,
                label: draftLabel,
                style: colors.tableButton,
              ),
            if (drafted) ...[
              const SizedBox(height: MiSpace.lg),
              if (_state == _DraftState.failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: MiSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: colors.onTable,
                      ),
                      const SizedBox(width: MiSpace.sm),
                      Expanded(
                        child: Text(
                          'Der Entwurf konnte gerade nicht erstellt werden. Du '
                          'kannst es gleich noch einmal versuchen oder selbst '
                          'schreiben.',
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              _LetterSheet(
                controller: _letter,
                streaming: streaming,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: MiSpace.md),
              Text(
                _selected.isEmpty
                    ? 'Unterschreibe mit deinem Namen, bevor du ihn abschickst. '
                        'Die Empfänger:innen trägst du in deiner Mail-App ein.'
                    : 'Unterschreibe mit deinem Namen, bevor du ihn abschickst. '
                        'Die Mail-App öffnet sich mit den ausgewählten '
                        'Fraktionsbüros in „An“.',
                style: muted,
              ),
              const SizedBox(height: MiSpace.base),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasLetter && !streaming ? _copy : null,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Kopieren'),
                    ),
                  ),
                  const SizedBox(width: MiSpace.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: hasLetter && !streaming ? _openMailApp : null,
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: const Text('Mail-App'),
                      style: colors.tableButton,
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
    final colors = context.mi;
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodyMedium?.copyWith(color: colors.onTableMuted);
    final recipients = this.recipients;
    final offices = recipients?.offices ?? const <FraktionOffice>[];
    final members = recipients?.members ?? const <CouncilMember>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('An', style: textTheme.titleMedium),
        const SizedBox(height: MiSpace.xs),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: MiSpace.sm),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (offices.isNotEmpty) ...[
          Text(
            'Die Büros der Fraktionen geben deine Nachricht an ihre '
            'Mitglieder weiter.',
            style: muted,
          ),
          const SizedBox(height: MiSpace.xs),
          for (final office in offices)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: office.email != null && selected.contains(office.email),
              onChanged:
                  office.email == null ? null : (_) => onToggle(office.email!),
              title: Text(
                office.fraktion,
                style: textTheme.bodyLarge?.copyWith(
                  color: office.email == null ? colors.onTableMuted : null,
                ),
              ),
              subtitle: Text(
                office.email ?? 'Adresse fehlt noch',
                style: textTheme.labelMedium?.copyWith(
                  color: colors.onTableMuted,
                ),
              ),
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
            childrenPadding: const EdgeInsets.only(bottom: MiSpace.sm),
            title: Text(
              'Mitglieder: ${recipients!.bodies.join(', ')} '
              '(${members.length})',
              style: textTheme.bodyLarge,
            ),
            children: [
              for (final member in members)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      member.fraktion != null
                          ? '${member.name} · ${member.fraktion}'
                          : member.name,
                      style: muted,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// The letter as a sheet of card stock lying on the table: ink text, and
/// editable in place.
class _LetterSheet extends StatelessWidget {
  const _LetterSheet({
    required this.controller,
    required this.streaming,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool streaming;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.mi;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, MiSpace.base, 20, 20),
      decoration: BoxDecoration(
        color: colors.cardStock,
        borderRadius: BorderRadius.circular(MiRadius.card),
        border: Border.all(color: colors.keyline),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Dein Brief',
                  style: text.labelMedium?.copyWith(
                    color: colors.onCard,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!streaming) ...[
                Icon(Icons.edit_outlined, size: 16, color: colors.onCardMuted),
                const SizedBox(width: MiSpace.xs),
                Flexible(
                  child: Text(
                    'Zum Ändern hineintippen',
                    style: text.labelMedium?.copyWith(
                      color: colors.onCardMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Divider(
            height: MiSpace.xl,
            color: colors.onCard.withValues(alpha: 0.12),
          ),
          TextField(
            controller: controller,
            readOnly: streaming,
            minLines: 8,
            maxLines: null,
            onChanged: onChanged,
            style: text.bodyLarge?.copyWith(
              color: colors.onCard,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
            decoration: InputDecoration(
              filled: false,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              hintText: 'Schreib hier deinen Brief.',
              hintStyle: text.bodyLarge?.copyWith(color: colors.onCardMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Divider(height: MiSpace.xl + MiSpace.base, color: color);
}
