import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/aktionen_tab.dart';
import 'package:meinimpact/src/features/feed/presentation/letter_screen.dart';
import 'package:meinimpact/src/features/tracking/data/action_log_store.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActionLog', () {
    test('keeps one entry per opportunity', () {
      final entry = _entry(_petition());
      final log =
          const ActionLog().withDone(entry).withDone(_entry(_petition()));

      expect(log.entries, hasLength(1));
      expect(log.entries.single.doneAt, entry.doneAt);
    });

    test('round-trips through JSON with its snapshot', () {
      final log = const ActionLog().withDone(_entry(_petition()));

      final restored = ActionLog.fromJson(log.toJson());
      final entry = restored.entries.single;

      expect(entry.opportunityId, 'petition-1');
      expect(entry.via, ActionVia.inAppBrowser);
      expect(entry.title, 'Petition zum Klimaschutz');
      expect(entry.kind, OpportunityKind.petition);
      expect(entry.sourceUrl, 'https://weact.campact.de/petitions/1');
      expect(entry.closesOn, DateTime(2026, 12, 1));
      expect(entry.affectedTags, ['Umwelt/Natur']);
    });
  });

  group('ActionLogStore', () {
    test('saves and loads the log', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = ActionLogStore();

      await store.save(const ActionLog().withDone(_entry(_petition())));

      expect((await store.load()).doneIds, {'petition-1'});
    });

    test('an unreadable log is kept aside and never breaks startup', () async {
      FlutterSecureStorage.setMockInitialValues({
        'action_log_v1': '{"entries": "not a list"}',
      });
      const store = ActionLogStore();

      expect((await store.load()).entries, isEmpty);
      expect(
        await const FlutterSecureStorage()
            .read(key: 'action_log_v1_unreadable'),
        '{"entries": "not a list"}',
      );
    });
  });

  group('Fertig in the feed', () {
    testWidgets('a done action leaves the feed right away and counts as acted',
        (tester) async {
      final harness = _Harness(openAction: (_, __) async => true);
      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      await _takeAction(tester, 'Petition zum Klimaschutz');

      expect(find.text('Petition zum Klimaschutz'), findsNothing);
      expect(find.text('Stark, erledigt!'), findsOneWidget);
      expect(harness.signals, [InterestSignal.opened, InterestSignal.acted]);
      expect(harness.done, {'petition-1': ActionVia.inAppBrowser});
    });

    testWidgets('closing the browser without Fertig changes nothing',
        (tester) async {
      final harness = _Harness(openAction: (_, __) async => false);
      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      await _takeAction(tester, 'Petition zum Klimaschutz');

      expect(find.text('Petition zum Klimaschutz'), findsOneWidget);
      expect(harness.signals, [InterestSignal.opened]);
      expect(harness.done, isEmpty);
    });

    testWidgets('the web teaser points to the app instead of taking part',
        (tester) async {
      var opened = false;
      final harness = _Harness(
        openAction: (_, __) async => opened = true,
        isWeb: true,
      );
      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      await _takeAction(tester, 'Petition zum Klimaschutz');

      expect(opened, isFalse);
      expect(find.text('Mitmachen geht in der App'), findsOneWidget);
      expect(harness.done, isEmpty);
    });

    testWidgets('a decision opens the letter, not the browser', (tester) async {
      var browserOpened = false;
      final harness = _Harness(
        opportunities: [_decision()],
        openAction: (_, __) async => browserOpened = true,
        openLetter:
            (_, __, {required repository, required onViewPaper}) async => true,
      );
      await tester.pumpWidget(harness);
      await tester.pumpAndSettle();

      await _takeAction(tester, 'Soll der Radweg gebaut werden?');

      expect(browserOpened, isFalse);
      expect(harness.done, {'decision-1': ActionVia.letter});
    });
  });

  group('LetterScreen', () {
    testWidgets('drafts with the notes, stays editable, Fertig pops true',
        (tester) async {
      final repository = _LetterRepository();
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await LetterScreen.open(
                context,
                _decision(),
                repository: repository,
                onViewPaper: () {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // No Fertig before there is a letter.
      expect(find.text('Fertig'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Ich fahre dort täglich.');
      await tester.tap(find.text('Brief erstellen'));
      await tester.pumpAndSettle();

      expect(repository.notes, 'Ich fahre dort täglich.');
      expect(
        find.text('Sehr geehrte Damen und Herren, bitte stimmen Sie zu.'),
        findsOneWidget,
      );
      expect(find.text('Neu erstellen'), findsOneWidget);

      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('offices are pre-selected and can be unticked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LetterScreen(
            opportunity: _decision(),
            repository: _LetterRepository(
              recipients: const LetterRecipients(
                bodies: ['Ausschuss für Stadtentwicklung'],
                members: [
                  CouncilMember(name: 'Anton Amsel', fraktion: 'CDU-Fraktion'),
                  CouncilMember(name: 'Bea Berg', fraktion: 'SPD-Fraktion'),
                ],
                offices: [
                  FraktionOffice(
                    fraktion: 'CDU-Fraktion',
                    email: 'cdu-fraktion@dresden.de',
                  ),
                  FraktionOffice(fraktion: 'Neue Fraktion'),
                  FraktionOffice(
                    fraktion: 'SPD-Fraktion',
                    email: 'spd-fraktion@dresden.de',
                  ),
                ],
              ),
            ),
            onViewPaper: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boxes = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect([for (final b in boxes) b.value], [true, false, true]);
      // An office without a known address cannot be ticked
      expect(boxes[1].onChanged, isNull);
      expect(find.text('Adresse fehlt noch'), findsOneWidget);
      expect(
        find.text('Mitglieder: Ausschuss für Stadtentwicklung (2)'),
        findsOneWidget,
      );

      await tester.tap(find.text('SPD-Fraktion'));
      await tester.pump();

      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .last
            .value,
        isFalse,
      );
    });

    group('Mail-App', () {
      Future<bool?> openAndSend(
        WidgetTester tester,
        Future<EmailSendResult> Function(Email) sendMail,
      ) async {
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => LetterScreen(
                      opportunity: _decision(),
                      repository: _LetterRepository(
                        recipients: const LetterRecipients(
                          offices: [
                            FraktionOffice(
                              fraktion: 'CDU-Fraktion',
                              email: 'cdu-fraktion@dresden.de',
                            ),
                            FraktionOffice(
                              fraktion: 'SPD-Fraktion',
                              email: 'spd-fraktion@dresden.de',
                            ),
                          ],
                        ),
                      ),
                      onViewPaper: () {},
                      sendMail: sendMail,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Brief erstellen'));
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(
          find.text('Mail-App'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.tap(find.text('Mail-App'));
        await tester.pumpAndSettle();
        return result;
      }

      testWidgets('carries letter and offices; a sent mail counts as Fertig',
          (tester) async {
        Email? sent;
        final result = await openAndSend(tester, (email) async {
          sent = email;
          return EmailSendResult.sent;
        });

        expect(sent!.recipients, [
          'cdu-fraktion@dresden.de',
          'spd-fraktion@dresden.de',
        ]);
        expect(sent!.subject, 'Ratsvorlage: Soll der Radweg gebaut werden?');
        expect(sent!.body, startsWith('Sehr geehrte Damen und Herren,'));
        expect(result, isTrue);
      });

      testWidgets('an unknown outcome leaves Fertig to the user',
          (tester) async {
        final result = await openAndSend(
          tester,
          (_) async => EmailSendResult.unknown,
        );

        expect(result, isNull);
        expect(find.text('Fertig'), findsOneWidget);
      });

      testWidgets('without a mail app the user is pointed to copying',
          (tester) async {
        await openAndSend(
          tester,
          (_) async => throw const FlutterEmailSenderNotAvailableException(),
        );

        expect(find.textContaining('Keine Mail-App gefunden'), findsOneWidget);
      });
    });

    testWidgets('district councils show names and no addresses',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LetterScreen(
            opportunity: _decision(),
            repository: _LetterRepository(
              recipients: const LetterRecipients(
                bodies: ['Stadtbezirksbeirat Blasewitz'],
                members: [CouncilMember(name: 'Carla Cron')],
              ),
            ),
            onViewPaper: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.textContaining('noch keine Adressen'), findsOneWidget);
    });

    testWidgets('a failed draft leaves the field to write by hand',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LetterScreen(
            opportunity: _decision(),
            repository: _LetterRepository(fail: true),
            onViewPaper: () {},
          ),
        ),
      );

      await tester.tap(find.text('Brief erstellen'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('konnte gerade nicht erstellt werden'),
        findsOneWidget,
      );
      expect(find.text('Dein Brief (bearbeitbar)'), findsOneWidget);
      expect(find.text('Fertig'), findsOneWidget);
    });
  });
}

Future<void> _takeAction(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
}

ActionLogEntry _entry(Opportunity opportunity) =>
    ActionLogEntry.fromOpportunity(
      opportunity,
      doneAt: DateTime.utc(2026, 11, 9, 14, 2),
      via: ActionVia.inAppBrowser,
    );

Opportunity _petition() => Opportunity(
      id: 'petition-1',
      sourceOrg: 'WeAct',
      sourceUrl: 'https://weact.campact.de/petitions/1',
      kind: OpportunityKind.petition,
      isAnnounced: false,
      region: 'bund',
      title: 'Petition zum Klimaschutz',
      summary: 'Eine Petition fordert mehr Klimaschutz.',
      affectedTags: const ['Umwelt/Natur'],
      werteRelevanz: const {},
      proArgumente: const [],
      contraArgumente: const [],
      personalImpactSnippets: const {},
      closesOn: DateTime(2026, 12, 1),
      firstSeenAt: DateTime(2026, 11, 1),
    );

Opportunity _decision() => Opportunity(
      id: 'decision-1',
      sourceOrg: 'Ratsinformationssystem Dresden',
      sourceUrl: 'https://ratsinfo.dresden.de/vo0050.asp?__kvonr=1',
      kind: OpportunityKind.decision,
      isAnnounced: false,
      region: 'dresden',
      organizer: 'Ausschuss für Stadtentwicklung',
      title: 'Soll der Radweg gebaut werden?',
      summary: 'Die Stadt will einen Radweg bauen.',
      affectedTags: const ['Verkehr'],
      werteRelevanz: const {},
      proArgumente: const [],
      contraArgumente: const [],
      personalImpactSnippets: const {},
      closesOn: DateTime(2026, 11, 26),
      firstSeenAt: DateTime(2026, 11, 8),
    );

/// The feed tab with an in-memory action log, as MeinImpactApp wires it.
class _Harness extends StatefulWidget {
  _Harness({
    required this.openAction,
    this.opportunities,
    this.isWeb = false,
    LetterOpener? openLetter,
  }) : openLetter = openLetter ??
            ((_, __, {required repository, required onViewPaper}) async =>
                false);

  final ActionOpener openAction;
  final LetterOpener openLetter;
  final bool isWeb;
  final List<Opportunity>? opportunities;
  final signals = <InterestSignal>[];
  final done = <String, ActionVia>{};

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  ActionLog _log = const ActionLog();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AktionenTab(
            opportunityRepository: _LetterRepository(
              opportunities: widget.opportunities ?? [_petition()],
            ),
            profile: const UserProfile(),
            doneIds: _log.doneIds,
            openAction: widget.openAction,
            openLetter: widget.openLetter,
            isWeb: widget.isWeb,
            onInterestSignal: (_, signal) => widget.signals.add(signal),
            onActionDone: (opportunity, via) {
              widget.done[opportunity.id] = via;
              setState(
                () => _log = _log.withDone(
                  ActionLogEntry.fromOpportunity(
                    opportunity,
                    doneAt: DateTime.now(),
                    via: via,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LetterRepository implements OpportunityRepository {
  _LetterRepository({
    this.opportunities = const [],
    this.fail = false,
    this.recipients = const LetterRecipients(),
  });

  final List<Opportunity> opportunities;
  final bool fail;
  final LetterRecipients recipients;
  String? notes;

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      recipients;

  @override
  Future<List<Opportunity>> pool() async => opportunities;

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) async* {
    this.notes = notes;
    if (fail) throw StateError('Mistral unavailable');
    yield 'Sehr geehrte Damen und Herren,';
    yield ' bitte stimmen Sie zu.';
  }
}
