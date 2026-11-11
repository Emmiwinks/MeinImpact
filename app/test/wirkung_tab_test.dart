import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/tracking/data/starred_actions_store.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';
import 'package:meinimpact/src/features/tracking/wirkung_tab.dart';

void main() {
  group('ImpactNewsFeed', () {
    test('parses the API feed by opportunity id', () {
      final feed = ImpactNewsFeed.fromJson({
        'opportunities': [
          {
            'opportunity_id': 'a',
            'checked_at': '2026-11-11T08:00:00Z',
            'items': [
              {
                'level': 'exact',
                'kind': 'statement',
                'title': 'Stadtrat äußert sich',
                'url': 'https://www.dnn.de/artikel',
                'snippet': 'Der Stadtrat …',
                'published_on': '2026-11-10',
              },
            ],
          },
          {
            'opportunity_id': 'b',
            'checked_at': '2026-11-11T09:00:00Z',
            'items': <Object?>[],
          },
        ],
      });

      final item = feed['a']!.items.single;
      expect(item.isStatement, isTrue);
      expect(item.isBackground, isFalse);
      expect(item.publishedOn, DateTime(2026, 11, 10));
      expect(feed['b']!.items, isEmpty);
      expect(feed['c'], isNull);
    });
  });

  group('WirkungTab', () {
    testWidgets('without done actions it explains how to start',
        (tester) async {
      await _pump(tester, const ImpactNewsFeed(), const []);

      expect(find.textContaining('Noch keine Aktion erledigt'), findsOneWidget);
    });

    testWidgets('shows only the own actions, each with its state',
        (tester) async {
      final feed = ImpactNewsFeed({
        'found': ImpactNewsEntry(
          checkedAt: DateTime.utc(2026, 11, 10),
          items: const [
            ImpactNewsItem(
              level: 'exact',
              kind: 'news',
              title: 'Petition übergeben',
              url: 'https://www.mdr.de/nachrichten/1',
              snippet: 'Die Unterschriften wurden übergeben.',
            ),
          ],
        ),
        'nothing': ImpactNewsEntry(checkedAt: DateTime.utc(2026, 11, 10)),
        'someone-elses': ImpactNewsEntry(
          checkedAt: DateTime.utc(2026, 11, 10),
          items: const [
            ImpactNewsItem(
              level: 'exact',
              kind: 'news',
              title: 'Fremde Meldung',
              url: 'https://example.org',
              snippet: '',
            ),
          ],
        ),
      });
      Uri? opened;
      await _pump(
        tester,
        feed,
        [_entry('found'), _entry('nothing'), _entry('waiting')],
        openLink: (url) async => opened = url,
      );

      expect(find.text('Petition übergeben'), findsOneWidget);
      expect(find.text('mdr.de'), findsOneWidget);
      expect(find.text('Fremde Meldung'), findsNothing);
      expect(
        find.textContaining('Noch keine Berichte gefunden'),
        findsOneWidget,
      );
      expect(find.textContaining('Wir suchen bald'), findsOneWidget);
      expect(find.text('3 Aktionen erledigt'), findsOneWidget);
      expect(find.text('1 davon mit Berichten'), findsOneWidget);

      await tester.ensureVisible(find.text('Petition übergeben'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Petition übergeben'));
      expect(opened, Uri.parse('https://www.mdr.de/nachrichten/1'));
    });

    testWidgets('only background news is labelled as such', (tester) async {
      final feed = ImpactNewsFeed({
        'found': ImpactNewsEntry(
          checkedAt: DateTime.utc(2026, 11, 10),
          items: const [
            ImpactNewsItem(
              level: 'background',
              kind: 'news',
              title: 'Klimaschutz in Sachsen',
              url: 'https://www.mdr.de/2',
              snippet: '',
            ),
          ],
        ),
      });
      await _pump(tester, feed, [_entry('found')]);

      expect(find.textContaining('Hintergrund zum Thema'), findsOneWidget);
      expect(find.text('Hintergrund'), findsOneWidget);
      // Background alone does not count as a report on the action.
      expect(find.text('Noch keine Berichte dazu'), findsOneWidget);
    });

    testWidgets('an action can be starred and the star is kept',
        (tester) async {
      final store = _MemoryStarStore({'other'});
      await _pump(
        tester,
        const ImpactNewsFeed(),
        [_entry('found')],
        starredStore: store,
      );

      await tester.tap(find.byTooltip('Folgen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Nicht mehr folgen'), findsOneWidget);
      expect(store.saved, {'other', 'found'});

      await tester.tap(find.byTooltip('Nicht mehr folgen'));
      await tester.pumpAndSettle();
      expect(store.saved, {'other'});
    });

    testWidgets('a failed feed still lists the actions', (tester) async {
      await _pump(tester, null, [_entry('found')]);

      expect(find.text('Petition found'), findsOneWidget);
      expect(find.textContaining('nicht geladen werden'), findsOneWidget);
    });
  });
}

Future<void> _pump(
  WidgetTester tester,
  ImpactNewsFeed? feed,
  List<ActionLogEntry> done, {
  LinkOpener? openLink,
  StarredActionsStore? starredStore,
}) async {
  // A tall phone, so every played card is built in the lazy list.
  tester.view.physicalSize = const Size(412, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: miTheme(Brightness.dark),
      home: Scaffold(
        body: WirkungTab(
          opportunityRepository: _NewsRepository(feed),
          doneActions: done,
          openLink: openLink ?? (_) async {},
          starredStore: starredStore ?? _MemoryStarStore(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ActionLogEntry _entry(String id) => ActionLogEntry(
      opportunityId: id,
      doneAt: DateTime.utc(2026, 11, 9),
      via: ActionVia.inAppBrowser,
      title: 'Petition $id',
      kind: OpportunityKind.petition,
      sourceOrg: 'WeAct',
      sourceUrl: 'https://weact.campact.de/petitions/$id',
    );

class _MemoryStarStore extends StarredActionsStore {
  _MemoryStarStore([Set<String> initial = const {}]) : saved = {...initial};

  Set<String> saved;

  @override
  Future<Set<String>> load() async => {...saved};

  @override
  Future<void> save(Set<String> ids) async => saved = {...ids};
}

class _NewsRepository implements OpportunityRepository {
  _NewsRepository(this.feed);

  // Null: the request fails.
  final ImpactNewsFeed? feed;

  @override
  Future<ImpactNewsFeed> impactNews() async =>
      feed ?? (throw StateError('offline'));

  @override
  Future<List<Opportunity>> pool() async => const [];

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) =>
      const Stream.empty();

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      const LetterRecipients();

  @override
  Future<void> markTracked(String opportunityId) async {}
}
