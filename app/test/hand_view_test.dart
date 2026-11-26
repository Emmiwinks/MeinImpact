import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:meinimpact/src/app/main_tab_screen.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/core/feedback/beta_feedback.dart';
import 'package:meinimpact/src/features/feed/data/hand_hints.dart';
import 'package:meinimpact/src/features/feed/data/opportunity_relevance_ranker.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/home_location.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/feed/domain/topic_tags.g.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/aktionen_tab.dart';
import 'package:meinimpact/src/features/feed/presentation/hand/action_card.dart';
import 'package:meinimpact/src/features/feed/presentation/hand/topic_art.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';

import 'support/text_finder.dart';

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
        factChips(_o('d', support: 692334, goal: 1000000), now),
        ['692.334 von 1.000.000 Unterstützer:innen'],
      );
      expect(thousands(0), '0');
      expect(thousands(999), '999');
      expect(thousands(75896), '75.896');
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
            interestTag: 'Umwelt/Natur',
          ),
        ),
        'Betrifft dich.',
      );
    });
  });

  group('card back', () {
    testWidgets('carries the action; the front only turns the card', (
      tester,
    ) async {
      var played = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: miTheme(Brightness.dark),
          home: Center(
            child: SizedBox(
              width: 320,
              height: 560,
              child: ActionCard(
                ranked: RankedOpportunity(
                  opportunity: _o('v', title: 'Frage?'),
                  matchedSnippet: null,
                ),
                actionLabel: 'Unterschreiben',
                onAction: () => played++,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(findText('Frage?'));
      await tester.pumpAndSettle();
      expect(played, 0);

      await tester.tap(find.widgetWithText(FilledButton, 'Unterschreiben'));
      expect(played, 1);
    });

    testWidgets('asks nothing about topics and turns back on a tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: miTheme(Brightness.dark),
          home: Center(
            child: SizedBox(
              width: 320,
              height: 560,
              child: ActionCard(
                ranked: RankedOpportunity(
                  opportunity: _o('v', tags: ['Wohnen/Miete']),
                  matchedSnippet: null,
                ),
                actionLabel: 'Unterschreiben',
                onAction: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ActionCard));
      await tester.pumpAndSettle();
      expect(findText('Zusammenfassung'), findsOneWidget);
      // Topics are learnt from what the user does, not voted on.
      expect(find.textContaining('öfter'), findsNothing);
      expect(find.textContaining('seltener'), findsNothing);
      await tester.tap(findText('Zusammenfassung'));
      await tester.pumpAndSettle();
      expect(findText('Zusammenfassung'), findsNothing);
    });
  });

  group('hand', () {
    testWidgets('deals the five best, swipes through and shows all', (
      tester,
    ) async {
      await tester.pumpWidget(_Tab(pool: _pool(7)));
      await tester.pumpAndSettle();

      // The throw hint stands in for the link until the first swipe.
      expect(findText('Alle 7 ansehen'), findsNothing);
      expect(_fanAt('Karte 1 von 5'), findsOneWidget);

      await tester.flingFrom(
        const Offset(400, 300),
        const Offset(-250, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 2 von 5'), findsOneWidget);
      expect(findText('Alle 7 ansehen'), findsOneWidget);

      // A drag too short to fling snaps back.
      await tester.dragFrom(const Offset(400, 300), const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 2 von 5'), findsOneWidget);

      await tester.tap(findText('Alle 7 ansehen'));
      await tester.pumpAndSettle();
      expect(findText('Alle Aktionen'), findsOneWidget);

      // Taking one that is not dealt into the hand puts it in front.
      await tester.scrollUntilVisible(findText('Frage 7?'), 200);
      await tester.tap(findText('Frage 7?'));
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 1 von 6'), findsOneWidget);
    });

    testWidgets('the next card is dealt face up after a turned one', (
      tester,
    ) async {
      await tester.pumpWidget(_Tab(pool: _pool(3)));
      await tester.pumpAndSettle();

      await tester.tap(findText('Frage 1?'));
      await tester.pumpAndSettle();
      expect(findText('Antwort 1'), findsOneWidget);

      await tester.flingFrom(
        const Offset(400, 300),
        const Offset(-250, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 2 von 3'), findsOneWidget);
      expect(findText('Antwort 2'), findsNothing);
      expect(findText('Antwort 1'), findsNothing);
    });

    testWidgets('the first time, the front card shows its back once', (
      tester,
    ) async {
      HandHints.current = HandHints.unseen();
      addTearDown(() => HandHints.current = HandHints.off());
      await tester.pumpWidget(_Tab(pool: _pool(3)));
      await tester.pump();
      await tester.pump();
      expect(findText('Antwort 1'), findsNothing);

      // Turned over by itself, held a moment, then back; the throw hint
      // comes after it.
      // In frames, so the timers and the turn both run.
      Future<void> wait(int ms) async {
        for (var i = 0; i < ms ~/ 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await wait(1500);
      expect(findText('Antwort 1'), findsOneWidget);
      expect(findText('Lange drücken zum Weglegen'), findsNothing);
      await wait(1500);
      expect(findText('Antwort 1'), findsNothing);
      expect(HandHints.current.turnSeen, isTrue);
      await wait(2000);
      expect(findText('Lange drücken zum Weglegen'), findsOneWidget);
      await tester.pumpAndSettle();

      // Seen once, a new hand does not do it again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_Tab(pool: _pool(3)));
      await tester.pump();
      await tester.pump();
      await wait(1500);
      expect(findText('Antwort 1'), findsNothing);
      await tester.pumpAndSettle();
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
      expect(
        findText('Das waren die 5, die am besten zu dir passen.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Gerade sind insgesamt 7 Aktionen offen.'),
        findsOneWidget,
      );
      // Only on the closing card; the link next to the dots steps back.
      expect(findText('Alle 7 ansehen'), findsOneWidget);

      await tester.tap(findText('Zurück zur ersten Karte'));
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
      expect(findText('Das waren alle offenen Aktionen.'), findsOneWidget);
      expect(find.textContaining('sobald Region, Land'), findsOneWidget);
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

      await _playFromBack(tester, 'Frage 1?');
      await tester.pump();
      await tester.pump(MiMotion.flight ~/ 2);
      // In flight: the copy on the overlay, back up as it was played, while
      // the card in the fan waits hidden until the log takes it out.
      expect(findText('Antwort 1'), findsNWidgets(2));
      expect(findText('Frage 1?'), findsNothing);
      await tester.pumpAndSettle();

      expect(findText('Antwort 1'), findsNothing);

      expect(findText('Frage 1?'), findsNothing);
      expect(_fanAt('Karte 1 von 1'), findsOneWidget);
      expect(tab.played, ['1']);
    });

    testWidgets('without animations the card turns and is played at once', (
      tester,
    ) async {
      final tab = _Tab(pool: _pool(2), done: true, disableAnimations: true);
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();

      await tester.tap(findText('Frage 1?'));
      await tester.pump();
      expect(findText('Antwort 1'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Petition ansehen'));
      await tester.pump();
      await tester.pump();
      expect(findText('Antwort 1'), findsNothing);
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
      expect(findText('Alle 1 ansehen'), findsNothing);

      await tester.tap(findText('Frage?'));
      await tester.pumpAndSettle();
      expect(findText('Dafür spricht'), findsOneWidget);
      expect(findText('Gut für Kinder'), findsOneWidget);
      expect(findText('Dagegen spricht'), findsOneWidget);
      expect(findText('Teuer'), findsOneWidget);
    });

    testWidgets('a bundle is one card; its options are ticked, not flown', (
      tester,
    ) async {
      OpportunityBundle option(String label, String difference) =>
          OpportunityBundle(
            id: 'ifg',
            header: '2 Petitionen · ähnliches Anliegen',
            title: 'Bleibt das Informationsfreiheitsgesetz?',
            summary: 'Die Koalition will es einschränken.',
            label: label,
            difference: difference,
          );
      final tab = _Tab(
        done: true,
        pool: [
          _o(
            'op',
            bundle: option('Bei openPetition', 'An den Bundestag.'),
            everyday: 5,
          ),
          _o('plain', title: 'Andere Frage?'),
          _o('we', bundle: option('Bei WeAct', 'An die SPD-Fraktion.')),
        ],
      );
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();

      expect(_fanAt('Karte 1 von 2'), findsOneWidget);
      expect(
        findText('Bleibt das Informationsfreiheitsgesetz?'),
        findsOneWidget,
      );
      expect(find.textContaining('2 Optionen'), findsOneWidget);

      await tester.tap(findText('Bleibt das Informationsfreiheitsgesetz?'));
      await tester.pumpAndSettle();
      expect(findText('2 Petitionen · ähnliches Anliegen'), findsOneWidget);
      expect(findText('An den Bundestag.'), findsOneWidget);
      expect(findText('An die SPD-Fraktion.'), findsOneWidget);

      await tester.tap(findText('Bei openPetition'));
      await tester.pumpAndSettle();
      // Done, but the card stays with the other option one tap away.
      expect(tab.played, ['op']);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(findText('An die SPD-Fraktion.'), findsOneWidget);
      expect(_fanAt('Karte 1 von 2'), findsOneWidget);

      await tester.tap(findText('Bei WeAct'));
      await tester.pumpAndSettle();
      expect(tab.played, ['op', 'we']);
      expect(findText('An die SPD-Fraktion.'), findsNothing);
      expect(_fanAt('Karte 1 von 1'), findsOneWidget);
    });

    testWidgets('a hand of two counts its cards', (tester) async {
      await tester.pumpWidget(_Tab(pool: _pool(2)));
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 1 von 2'), findsOneWidget);
    });

    testWidgets('while loading, the deck lies face down', (tester) async {
      await tester.pumpWidget(_Tab(pool: _pool(1), slow: true));
      await tester.pump();
      expect(findText('Deine Karten werden gemischt …'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('throwing a card away', () {
    final posts = <(String, Map<String, Object?>)>[];
    setUp(() {
      posts.clear();
      BetaFeedback.current = BetaFeedback(
        post: (path, body) async => posts.add((path, body)),
      );
    });
    tearDown(() => BetaFeedback.current = BetaFeedback.off());

    const sheetTitle = 'Warum legst du sie weg?';
    final trash = find.byWidgetPredicate(
      (w) => w is Icon && w.semanticLabel == 'Papierkorb',
    );

    // A long press on [from], then carried to the trash can, or up a little
    // without [toTrash], and let go.
    Future<void> carry(
      WidgetTester tester, {
      Offset from = const Offset(400, 250),
      bool toTrash = true,
    }) async {
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pump(MiMotion.quick);
      final to = toTrash ? tester.getCenter(trash) : from - const Offset(0, 80);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('the hint stays until the hand is swiped', (tester) async {
      await tester.pumpWidget(_Tab(pool: _pool(3)));
      final hint = findText('Lange drücken zum Weglegen');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));
      expect(hint, findsOneWidget);

      await tester.flingFrom(
        const Offset(400, 300),
        const Offset(-250, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
    });

    testWidgets('with animations off, the hint still shows', (tester) async {
      // Android's "Remove animations" cuts ordinary animations to 5 %.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(_Tab(pool: _pool(3)));
      await tester.pumpAndSettle();
      expect(findText('Lange drücken zum Weglegen'), findsOneWidget);
    });

    testWidgets('dropped in the trash, it goes with its reason and ranking', (
      tester,
    ) async {
      final tab = _Tab(pool: _pool(3));
      await tester.pumpWidget(tab);
      // Never thrown one away: the hint says how, and goes once the card
      // is lifted.
      final hint = findText('Lange drücken zum Weglegen');
      await tester.pumpAndSettle();
      expect(hint, findsOneWidget);

      await carry(tester);
      expect(findText(sheetTitle), findsOneWidget);
      await tester.tap(findText('Zu weit weg'));
      await tester.pumpAndSettle();

      expect(findText(sheetTitle), findsNothing);
      expect(findText('Frage 1?'), findsNothing);
      expect(_fanAt('Karte 1 von 2'), findsOneWidget);
      expect(tab.dismissed, {'1'});
      final (path, body) = posts.single;
      expect(path, '/v1/feedback/card');
      expect(body['opportunity_id'], '1');
      expect(body['reason'], 'too_far');
      expect(body.containsKey('note'), isFalse);
      final ranking = body['ranking']! as Map<String, Object?>;
      expect(ranking['position'], 0);
      expect(ranking.keys, {
        'position',
        'score',
        'appeal',
        'situation',
        'interest',
        'locality',
        'haltung',
        'exploration',
      });
    });

    testWidgets('let go elsewhere, it goes back into the hand', (tester) async {
      final tab = _Tab(pool: _pool(3));
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();
      await carry(tester, toTrash: false);
      expect(findText(sheetTitle), findsNothing);
      expect(_fanAt('Karte 1 von 3'), findsOneWidget);
      expect(tab.dismissed, isEmpty);
      // The hand still swipes and the dots are back.
      await tester.flingFrom(
        const Offset(400, 300),
        const Offset(-250, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(_fanAt('Karte 2 von 3'), findsOneWidget);
    });

    testWidgets('kept after all it comes back; skipped it goes unexplained', (
      tester,
    ) async {
      final tab = _Tab(pool: _pool(3));
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();

      await carry(tester);
      await tester.tap(findText('Doch behalten'));
      await tester.pumpAndSettle();
      expect(findText('Frage 1?'), findsOneWidget);
      expect(_fanAt('Karte 1 von 3'), findsOneWidget);
      expect(tab.dismissed, isEmpty);

      await carry(tester);
      await tester.tap(findText('Überspringen'));
      await tester.pumpAndSettle();
      expect(findText('Frage 1?'), findsNothing);
      expect(tab.dismissed, {'1'});
      expect(posts, isEmpty);
    });

    testWidgets('turned over, its text lifts it too; a reason takes a note', (
      tester,
    ) async {
      final tab = _Tab(
        pool: [
          _o(
            '1',
            title: 'Lange Frage?',
            pro: [for (var i = 0; i < 12; i++) 'Grund $i'],
          ),
          _o('2'),
        ],
      );
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();
      await tester.tap(findText('Lange Frage?'));
      await tester.pumpAndSettle();

      // On the scrolling text, a drag still scrolls...
      final text = tester.getCenter(findText('Zusammenfassung'));
      await tester.dragFrom(text, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(findText(sheetTitle), findsNothing);
      // ...and a long press lifts the card.
      await carry(tester, from: tester.getCenter(findText('Grund 3')));
      await tester.tap(findText('Möchte ich nicht unterstützen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Zu teuer.  ');
      await tester.tap(findText('Senden'));
      await tester.pumpAndSettle();

      expect(tab.dismissed, {'1'});
      expect(posts.single.$2['reason'], 'dont_support');
      expect(posts.single.$2['note'], 'Zu teuer.');
    });

    testWidgets('not interested means fewer cards of the topic', (
      tester,
    ) async {
      final tab = _Tab(pool: _pool(3));
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();

      await carry(tester);
      expect(findText('Schon erledigt'), findsNothing);
      await tester.tap(findText('Thema interessiert mich nicht'));
      await tester.pumpAndSettle();
      expect(tab.signals.single.$2, InterestSignal.notInterested);
      expect(tab.signals.single.$1, _pool(3).first.affectedTags);
    });

    testWidgets('screen readers can throw a card away', (tester) async {
      final handle = tester.ensureSemantics();
      final tab = _Tab(pool: _pool(2));
      await tester.pumpWidget(tab);
      await tester.pumpAndSettle();

      final fan = find.semantics.byLabel(RegExp('^Karte 1')).evaluate().single;
      final action = fan.getSemanticsData().customSemanticsActionIds!.single;
      fan.owner!.performAction(
        fan.id,
        SemanticsAction.customAction,
        action,
      );
      await tester.pumpAndSettle();
      await tester.tap(findText('Überspringen'));
      await tester.pumpAndSettle();
      expect(tab.dismissed, {'1'});
      handle.dispose();
    });
  });

  testWidgets('Feedback from the profile sends kind, words and the open tab', (
    tester,
  ) async {
    final posts = <(String, Map<String, Object?>)>[];
    var offline = true;
    BetaFeedback.current = BetaFeedback(
      post: (path, body) async {
        if (offline) throw Exception('offline');
        posts.add((path, body));
      },
    );
    addTearDown(() => BetaFeedback.current = BetaFeedback.off());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: MainTabScreen(opportunityRepository: _Repository(const [])),
      ),
    );
    await tester.pumpAndSettle();
    // Not on the hand: a row at the end of the profile.
    expect(findText('Feedback'), findsNothing);
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('row-feedback')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('row-feedback')));
    await tester.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, 'Senden');
    // Kind and words first.
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(findText('Idee'));
    await tester.enterText(find.byType(TextField), 'Mehr Karten zu Kultur');
    await tester.pump();

    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.textContaining('Das ging gerade nicht raus'), findsOneWidget);

    offline = false;
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(findText('Danke! Ist angekommen.'), findsOneWidget);
    final (path, body) = posts.single;
    expect(path, '/v1/feedback');
    expect(body['kind'], 'idea');
    expect(body['message'], 'Mehr Karten zu Kultur');
    expect(body['screen'], 'profil');
    expect(body['platform'], 'android');
    // The sheet left the tab where it was.
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
  });

  testWidgets('Wirkung counts the actions done since it was last opened', (
    tester,
  ) async {
    Widget shell(List<ActionLogEntry> done) => MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: miTheme(Brightness.light),
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

    // The streak's flame shows a number too.
    final unseen = find.descendant(
      of: find.byType(Badge),
      matching: findText('1'),
    );
    await tester.pumpWidget(shell(const []));
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsOneWidget);
    expect(unseen, findsNothing);

    await tester.pumpWidget(shell([entry]));
    await tester.pumpAndSettle();
    expect(unseen, findsOneWidget);

    await tester.tap(findText('Mein Impact'));
    await tester.pumpAndSettle();
    await tester.tap(findText('Meine Aktionen'));
    await tester.pumpAndSettle();
    expect(unseen, findsNothing);
  });

  testWidgets(
      'a profile edit re-ranks the loaded hand, a learned signal does not', (
    tester,
  ) async {
    final repository = _Repository([
      _o('allgemein', everyday: 5),
      Opportunity.fromJson({
        'id': 'miete',
        'source_org': 'WeAct',
        'source_url': 'https://example.org/miete',
        'kind': 'petition',
        'region': 'dresden',
        'title': 'Frage miete?',
        'summary': 'Zusammenfassung',
        'lebenslagen': ['mieter'],
        'everyday_relevance': 3,
        'accessibility': 3,
        'first_seen_at': '2026-11-01T00:00:00Z',
      }),
    ]);
    Future<void> pump(UserProfile profile, int revision) => tester.pumpWidget(
          MaterialApp(
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: AktionenTab(
                opportunityRepository: repository,
                profile: profile,
                profileRevision: revision,
              ),
            ),
          ),
        );
    String front() => tester
        .widgetList<ActionCard>(find.byType(ActionCard))
        .firstWhere((c) => c.isFront)
        .ranked
        .opportunity
        .id;
    const picked = UserProfile(lebenslagen: {'mieter'});

    await pump(const UserProfile(), 0);
    await tester.pumpAndSettle();
    expect(front(), 'allgemein');

    // Same revision: a learned signal changed the profile, the hand stays
    await pump(picked, 0);
    await tester.pumpAndSettle();
    expect(front(), 'allgemein');

    await pump(picked, 1);
    await tester.pumpAndSettle();
    expect(front(), 'miete');
    expect(repository.fetches, 1);
  });
}

// The fan's own node; its children's words follow the label.
Finder _fanAt(String label) => find.bySemanticsLabel(RegExp('^$label'));

// How a user plays a card: turn it over by its question, then press the
// action on its back.
Future<void> _playFromBack(WidgetTester tester, String title) async {
  await tester.tap(findText(title));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Petition ansehen'));
}

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
  OpportunityBundle? bundle,
}) =>
    Opportunity(
      bundle: bundle,
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
  final dismissed = <String>{};
  final signals = <(List<String>, InterestSignal)>[];

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
          dismissedIds: {...widget.dismissed},
          onDismissed: (ids) => setState(() => widget.dismissed.addAll(ids)),
          onInterestSignal: (tags, signal) =>
              widget.signals.add((tags, signal)),
        ),
      ),
    );
  }
}

class _Repository implements OpportunityRepository {
  _Repository(this.items, {this.slow = false});

  final List<Opportunity> items;
  final bool slow;
  int fetches = 0;

  @override
  Future<List<Opportunity>> pool({String? kreis}) async {
    fetches++;
    if (slow) await Future<void>.delayed(const Duration(milliseconds: 50));
    return items;
  }

  @override
  Future<PlzLookup?> locate(String plz) async => null;

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
