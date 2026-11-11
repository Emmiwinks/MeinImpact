import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:meinimpact/src/app/main_tab_screen.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/feed/domain/topic_tags.g.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/aktionen_tab.dart';
import 'package:meinimpact/src/features/feed/presentation/hand/action_card.dart';
import 'package:meinimpact/src/features/feed/presentation/hand/topic_art.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';

void main() {
  group('topic art', () {
    test('every topic tag has its own picture', () {
      expect(topicsWithArt.toSet(), kTopicTags.toSet());
    });

    testWidgets('paints every topic and the fallback in both themes', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: miTheme(brightness),
            home: Wrap(
              children: [
                for (final tag in [...kTopicTags, 'Unbekannt'])
                  SizedBox(
                    width: 120,
                    height: 60,
                    child: TopicArt(look: TopicLook.of(_o('x', tags: [tag]))),
                  ),
              ],
            ),
          ),
        );
        expect(find.byType(TopicArt), findsNWidgets(kTopicTags.length + 1));
      }
    });

    test('a topic always gets the same colour; no topic falls back to kind',
        () {
      const colors = MiColors.dark;
      final a = TopicLook.of(_o('a', tags: ['Wohnen/Miete']));
      final b = TopicLook.of(_o('b', tags: ['Wohnen/Miete', 'Sicherheit']));
      expect(a.face(colors), b.face(colors));
      expect(a.accent(colors), isNot(a.face(colors)));
      final none = TopicLook.of(_o('c', tags: []));
      expect(none.tag, isNull);
      expect(none.index, OpportunityKind.petition.index);
    });

    test('theme colours interpolate and copy', () {
      final mid = MiColors.dark.lerp(MiColors.light, 0.5);
      expect(mid.table, isNot(MiColors.dark.table));
      expect(MiColors.dark.lerp(null, 0.5), MiColors.dark);
      expect(MiColors.dark.copyWith(table: Colors.red).table, Colors.red);
      expect(MiColors.dark.copyWith().onTable, MiColors.dark.onTable);
    });
  });

  group('card texts', () {
    final now = DateTime(2026, 11, 11);

    test('meta line names kind and timing', () {
      expect(metaLine(_o('a'), now), 'Petition');
      expect(metaLine(_o('a', closes: now), now), 'Petition · endet heute');
      expect(
        metaLine(_o('a', closes: DateTime(2026, 11, 12)), now),
        'Petition · noch 1 Tag',
      );
      expect(
        metaLine(_o('a', closes: DateTime(2026, 11, 20)), now),
        'Petition · noch 9 Tage',
      );
      const decision = OpportunityKind.decision;
      expect(
        metaLine(_o('a', kind: decision, closes: now), now),
        'Abstimmung im Rat · heute',
      );
      expect(
        metaLine(_o('a', kind: decision, closes: DateTime(2026, 11, 12)), now),
        'Abstimmung im Rat · morgen',
      );
      expect(
        metaLine(_o('a', kind: decision, closes: DateTime(2026, 11, 16)), now),
        'Abstimmung im Rat · in 5 Tagen',
      );
      expect(
        metaLine(_o('a', announced: true, opens: DateTime(2026, 12, 1)), now),
        'Petition · ab 1.12.2026',
      );
    });

    test('fact chips carry registry facts only', () {
      expect(
        factChips(
          _o(
            'a',
            closes: DateTime(2026, 11, 20),
            support: 12,
            goal: 50,
            place: 'Ortsbeirat Pieschen',
            districts: ['Pieschen'],
          ),
          now,
        ),
        [
          'Bis 20.11.2026',
          '12 von 50 Unterstützer:innen',
          'Ortsbeirat Pieschen',
          'Pieschen',
        ],
      );
      expect(
        factChips(
          _o(
            'b',
            kind: OpportunityKind.decision,
            closes: DateTime(2026, 11, 20),
            support: 7,
          ),
          now,
        ),
        ['Sitzung am 20.11.2026', '7 Unterstützer:innen'],
      );
      expect(
        factChips(_o('c', announced: true, opens: DateTime(2026, 12, 1)), now),
        ['Ab 1.12.2026'],
      );
    });

    test('the personal sentence is the first reason', () {
      expect(
        whyLine(
          RankedOpportunity(
            opportunity: _o('p'),
            matchedSnippet: 'Betrifft dich.',
            werteAlignment: 0.5,
            interestTag: 'Umwelt/Natur',
          ),
        ),
        'Betrifft dich.',
      );
    });
  });

  group('hand', () {
    testWidgets('deals the five best, swipes through and shows all', (
      tester,
    ) async {
      await tester.pumpWidget(_Tab(pool: _pool(7)));
      await tester.pumpAndSettle();

      expect(find.text('Alle 7 ansehen'), findsOneWidget);
      expect(_fanAt('Karte 1 von 5'), findsOneWidget);

      await tester.flingFrom(
        const Offset(400, 300),
        const Offset(-250, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 2 von 5'), findsOneWidget);

      // A drag too short to fling snaps back.
      await tester.dragFrom(const Offset(400, 300), const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 2 von 5'), findsOneWidget);

      await tester.tap(find.text('Alle 7 ansehen'));
      await tester.pumpAndSettle();
      expect(find.text('Alle Aktionen'), findsOneWidget);

      // Taking one that is not dealt into the hand puts it in front.
      await tester.scrollUntilVisible(find.text('Frage 7?'), 200);
      await tester.tap(find.text('Frage 7?'));
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 1 von 6'), findsOneWidget);
    });

    testWidgets('after the last card the hand ends', (tester) async {
      await tester.pumpWidget(_Tab(pool: _pool(7)));
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        await tester.flingFrom(
          const Offset(400, 300),
          const Offset(-250, 0),
          900,
        );
        await tester.pumpAndSettle();
      }
      expect(_fanAt('Ende deiner Hand'), findsOneWidget);
      expect(find.text('Das war deine 5.'), findsOneWidget);
      // Only on the closing card; the link next to the dots steps back.
      expect(find.text('Alle 7 ansehen'), findsOneWidget);

      await tester.tap(find.text('Zurück zur ersten Karte'));
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 1 von 5'), findsOneWidget);
    });

    testWidgets('a hand holding everything says there is no more', (
      tester,
    ) async {
      await tester.pumpWidget(_Tab(pool: _pool(1)));
      await tester.pumpAndSettle();
      await tester.flingFrom(
        const Offset(400, 300),
        const Offset(-250, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(find.text('Das war deine Karte.'), findsOneWidget);
      expect(find.textContaining('Mehr gibt es gerade nicht.'), findsOneWidget);
    });

    testWidgets('screen readers can step through the hand', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_Tab(pool: _pool(3)));
      await tester.pumpAndSettle();

      tester.semantics.increase(find.semantics.byLabel(RegExp('^Karte 1')));
      await tester.pumpAndSettle();
      tester.semantics.decrease(find.semantics.byLabel(RegExp('^Karte 2')));
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 1 von 3'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a played card flies off and the next one moves up', (
      tester,
    ) async {
      final tab = _Tab(pool: _pool(2), done: true);
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();

      await tester.tap(_playable);
      await tester.pump();
      await tester.pump(MiMotion.flight ~/ 2);
      // In flight: the copy on the overlay, while the card in the fan waits
      // hidden until the log takes it out.
      expect(find.text('Frage 1?'), findsNWidgets(2));
      await tester.pumpAndSettle();

      expect(find.text('Frage 1?'), findsNothing);
      expect(_fanAt('Karte 1 von 1'), findsOneWidget);
      expect(tab.played, ['1']);
    });

    testWidgets('without animations the card turns and is played at once', (
      tester,
    ) async {
      final tab = _Tab(pool: _pool(2), done: true, disableAnimations: true);
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Frage 1?'));
      await tester.pump();
      expect(find.text('Antwort 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Karte umdrehen'));
      await tester.pump();
      expect(find.text('Antwort 1'), findsNothing);

      await tester.tap(_playable);
      await tester.pump();
      await tester.pump();
      expect(find.text('Frage 1?'), findsNothing);
      expect(tab.played, ['1']);
    });

    testWidgets('a card turned over shows both sides of the argument', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Tab(
          pool: [
            _o(
              'a',
              title: 'Frage?',
              pro: ['Gut für Kinder'],
              contra: ['Teuer'],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 1 von 1'), findsOneWidget);
      expect(find.text('Alle 1 ansehen'), findsNothing);

      await tester.tap(find.text('Frage?'));
      await tester.pumpAndSettle();
      expect(find.text('Dafür spricht'), findsOneWidget);
      expect(find.text('Gut für Kinder'), findsOneWidget);
      expect(find.text('Dagegen spricht'), findsOneWidget);
      expect(find.text('Teuer'), findsOneWidget);
    });

    testWidgets('a hand of two counts its cards', (tester) async {
      await tester.pumpWidget(_Tab(pool: _pool(2)));
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 1 von 2'), findsOneWidget);
    });

    testWidgets('while loading, the deck lies face down', (tester) async {
      await tester.pumpWidget(_Tab(pool: _pool(1), slow: true));
      await tester.pump();
      expect(find.text('Deine Karten werden gemischt …'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('Wirkung counts the actions done since it was last opened', (
    tester,
  ) async {
    Widget shell(List<ActionLogEntry> done) => MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: legacyTheme(),
          home: MainTabScreen(
            opportunityRepository: _Repository(const []),
            doneActions: done,
          ),
        );
    final entry = ActionLogEntry.fromOpportunity(
      _o('1'),
      doneAt: DateTime(2026, 11, 11),
      via: ActionVia.inAppBrowser,
    );

    await tester.pumpWidget(shell(const []));
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.pumpWidget(shell([entry]));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('Mein Impact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meine Aktionen'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);
  });
}

// The fan's own node; its children's words follow the label.
Finder _fanAt(String label) => find.bySemanticsLabel(RegExp('^$label'));

// Only the front card's button is live; the cards behind carry one too.
final _playable = find.byWidgetPredicate(
  (widget) => widget is FilledButton && widget.onPressed != null,
);

List<Opportunity> _pool(int count) => [
      for (var i = 1; i <= count; i++)
        _o(
          '$i',
          title: 'Frage $i?',
          summary: 'Antwort $i',
          tags: [kTopicTags[i % kTopicTags.length]],
          // Earlier ones rank higher.
          everyday: 5 - i ~/ 3,
        ),
    ];

Opportunity _o(
  String id, {
  String? title,
  String summary = 'Zusammenfassung',
  OpportunityKind kind = OpportunityKind.petition,
  List<String> tags = const ['Umwelt/Natur'],
  List<String> pro = const [],
  List<String> contra = const [],
  DateTime? closes,
  DateTime? opens,
  bool announced = false,
  int? support,
  int? goal,
  String? place,
  List<String> districts = const [],
  int everyday = 3,
}) =>
    Opportunity(
      id: id,
      sourceOrg: 'WeAct',
      sourceUrl: 'https://example.org/$id',
      kind: kind,
      isAnnounced: announced,
      region: 'dresden',
      organizer: place,
      title: title ?? 'Frage $id?',
      summary: summary,
      affectedTags: tags,
      districts: districts,
      werteRelevanz: const {},
      proArgumente: pro,
      contraArgumente: contra,
      personalImpactSnippets: const {},
      opensOn: opens,
      closesOn: closes,
      supportCount: support,
      supportGoal: goal,
      everydayRelevance: everyday,
      accessibility: 3,
      firstSeenAt: DateTime(2026, 11, 1),
    );

/// The Für-dich tab with an in-memory action log and an action site that
/// reports [done] instead of opening a WebView.
class _Tab extends StatefulWidget {
  _Tab({
    required this.pool,
    this.done = false,
    this.slow = false,
    this.disableAnimations = false,
  });

  final List<Opportunity> pool;
  final bool done;
  final bool slow;
  final bool disableAnimations;
  final played = <String>[];

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  late final _repository = _Repository(widget.pool, slow: widget.slow);
  final _doneIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: widget.disableAnimations,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: AktionenTab(
          opportunityRepository: _repository,
          profile: const UserProfile(),
          doneIds: {..._doneIds},
          openAction: (_, __) async => widget.done,
          onActionDone: (opportunity, _) {
            widget.played.add(opportunity.id);
            setState(() => _doneIds.add(opportunity.id));
          },
        ),
      ),
    );
  }
}

class _Repository implements OpportunityRepository {
  _Repository(this.items, {this.slow = false});

  final List<Opportunity> items;
  final bool slow;

  @override
  Future<List<Opportunity>> pool() async {
    if (slow) await Future<void>.delayed(const Duration(milliseconds: 50));
    return items;
  }

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

  @override
  Future<ImpactNewsFeed> impactNews() async => const ImpactNewsFeed();
}
