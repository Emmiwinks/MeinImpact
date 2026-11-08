import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/aktionen_tab.dart';
import 'package:meinimpact/src/features/tracking/data/action_log_store.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActionLog', () {
    test('keeps one entry per opportunity and can undo it', () {
      final entry = _entry(_petition());
      final log =
          const ActionLog().withDone(entry).withDone(_entry(_petition()));

      expect(log.entries, hasLength(1));
      expect(log.entries.single.doneAt, entry.doneAt);
      expect(log.without('petition-1').isDone('petition-1'), isFalse);
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
    testWidgets('a done action leaves the feed and counts as acted',
        (tester) async {
      final signals = <InterestSignal>[];
      await tester.pumpWidget(
        _Harness(openAction: (_, __) async => true, signals: signals),
      );
      await tester.pumpAndSettle();

      await _takeAction(tester);
      expect(find.text('Stark, erledigt!'), findsOneWidget);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();

      expect(find.text('Petition zum Klimaschutz'), findsNothing);
      expect(signals, [InterestSignal.opened, InterestSignal.acted]);
    });

    testWidgets('undo brings the action back without learning from it',
        (tester) async {
      final signals = <InterestSignal>[];
      await tester.pumpWidget(
        _Harness(openAction: (_, __) async => true, signals: signals),
      );
      await tester.pumpAndSettle();

      await _takeAction(tester);
      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();

      expect(find.text('Petition zum Klimaschutz'), findsOneWidget);
      expect(signals, [InterestSignal.opened]);
    });

    testWidgets('closing the browser without Fertig changes nothing',
        (tester) async {
      final signals = <InterestSignal>[];
      await tester.pumpWidget(
        _Harness(openAction: (_, __) async => false, signals: signals),
      );
      await tester.pumpAndSettle();

      await _takeAction(tester);

      expect(find.text('Stark, erledigt!'), findsNothing);
      expect(find.text('Petition zum Klimaschutz'), findsOneWidget);
      expect(signals, [InterestSignal.opened]);
    });
  });
}

Future<void> _takeAction(WidgetTester tester) async {
  await tester.tap(find.text('Petition zum Klimaschutz'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Petition unterschreiben'));
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

/// The feed tab with an in-memory action log, as MeinImpactApp wires it.
class _Harness extends StatefulWidget {
  const _Harness({required this.openAction, required this.signals});

  final ActionOpener openAction;
  final List<InterestSignal> signals;

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
            opportunityRepository: _PoolRepository(),
            profile: const UserProfile(),
            doneIds: _log.doneIds,
            openAction: widget.openAction,
            onInterestSignal: (_, signal) => widget.signals.add(signal),
            onActionDone: (opportunity, via) => setState(
              () => _log = _log.withDone(
                ActionLogEntry.fromOpportunity(
                  opportunity,
                  doneAt: DateTime.now(),
                  via: via,
                ),
              ),
            ),
            onActionUndone: (id) => setState(() => _log = _log.without(id)),
          ),
        ),
      ),
    );
  }
}

class _PoolRepository implements OpportunityRepository {
  @override
  Future<List<Opportunity>> pool() async => [_petition()];

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];
}
