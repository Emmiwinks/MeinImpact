// Renders the redesigned screens with the real fonts at phone size and
// writes PNGs to ../.impeccable/review/ for the design review. Not part of
// the normal suite: run with `flutter test test_screenshots`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:meinimpact/src/app/main_tab_screen.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/local_coverage.dart';
import 'package:meinimpact/src/features/feed/domain/home_location.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/aktionen_tab.dart';
import 'package:meinimpact/src/features/feed/presentation/hand/action_card.dart';
import 'package:meinimpact/src/features/feed/presentation/letter_screen.dart';
import 'package:meinimpact/src/features/onboarding/rucksack/rucksack_screen.dart';
import 'package:meinimpact/src/features/onboarding/value_profile_screen.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';
import 'package:meinimpact/src/features/tracking/domain/progress.dart';
import 'package:meinimpact/src/features/tracking/progress_widgets.dart';
import 'package:meinimpact/src/features/tracking/streak_flame.dart';

const _out = '../.impeccable/review';
final _boundary = GlobalKey();

void main() {
  setUpAll(_loadFonts);

  testWidgets('palettes, dark', (t) => _shootPalettes(t, Brightness.dark));
  testWidgets('palettes, light', (t) => _shootPalettes(t, Brightness.light));

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    Brightness brightness = Brightness.dark,
    double textScale = 1,
    double pixelRatio = 2,
    List<Opportunity>? pool,
    UserProfile profile = const UserProfile(
      lebenslagen: {'eltern', 'oepnv', 'mieter'},
    ),
    List<ActionLogEntry> doneActions = const [],
    ImpactNewsFeed news = const ImpactNewsFeed(),
    Future<void> Function(WidgetTester tester)? act,
    // False to catch a motion midway: [act] then pumps itself.
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    // flutter_test paints shadows without blur by default; the device does
    // not. The binding checks the flag is back on when the test ends.
    debugDisableShadows = false;

    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: miTheme(Brightness.light),
          home: MainTabScreen(
            opportunityRepository: _Pool(pool ?? _opportunities(), news),
            profile: profile,
            doneActions: doneActions,
            doneIds: ActionLog(doneActions).doneIds,
            onActionDone: (_, __) {},
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The pool, then the hand.
      await tester.pump();
      await tester.pump();
    }
    if (act != null) {
      await act(tester);
      if (settle) await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final boundary = _boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_out/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
    debugDisableShadows = true;
  }

  testWidgets('hand, dark', (t) => shoot(t, 'phone-hand-dark'));
  testWidgets(
    'hand, light',
    (t) => shoot(t, 'phone-hand-light', brightness: Brightness.light),
  );
  testWidgets(
    'card back, dark',
    (t) => shoot(
      t,
      'phone-back-dark',
      act: (t) => t.tap(find.textContaining('Blitzer')),
    ),
  );
  testWidgets(
    'card back, light',
    (t) => shoot(
      t,
      'phone-back-light',
      brightness: Brightness.light,
      act: (t) => t.tap(find.textContaining('Blitzer')),
    ),
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'impact, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-impact-${brightness.name}',
        brightness: brightness,
        doneActions: _pitchDone(),
        news: _pitchNews(),
        act: (t) => t.tap(find.text('Mein Impact')),
      ),
    );
  }
  testWidgets(
    'longest title, dark',
    (t) => shoot(
      t,
      'phone-long-title-dark',
      act: (t) async {
        // Swipe through to the fourth card, the council decision.
        for (var i = 0; i < 3; i++) {
          await t.flingFrom(const Offset(195, 300), const Offset(-200, 0), 800);
          await t.pumpAndSettle();
        }
      },
    ),
  );
  // A bundled card, with real texts from the pool: two petitions against
  // one law.
  OpportunityBundle ifg(String label, String difference) => OpportunityBundle(
        id: 'ifg',
        header: '2 Petitionen · ähnliches Anliegen',
        title: 'Bleibt das Informationsfreiheitsgesetz?',
        summary: 'Die Koalition will das Informationsfreiheitsgesetz '
            'einschränken. Damit kann heute jede:r ohne Begründung Auskunft '
            'von Bundesbehörden verlangen.',
        label: label,
        difference: difference,
      );
  final bundlePool = [
    _o(
      'ifg-op',
      kind: OpportunityKind.petition,
      source: 'openPetition',
      title: 'Darf der Staat Geheimnisse vor uns haben?',
      summary: '',
      tags: ['Demokratie/Mitbestimmung'],
      closes: 44,
      support: 75896,
      bundle: ifg(
        'Bei openPetition, an den Bundestag',
        'Fordert, dass das Gesetz bleibt, wie es ist: kein „berechtigtes '
            'Interesse“ als Hürde.',
      ),
    ),
    _o(
      'ifg-we',
      kind: OpportunityKind.petition,
      source: 'WeAct',
      title: 'Darf der Staat Geheimnisse vor uns haben?',
      summary: '',
      tags: ['Demokratie/Mitbestimmung'],
      support: 692334,
      bundle: ifg(
        'Bei WeAct, an die SPD-Fraktion',
        'Fordert, dass die SPD den Plan der Koalition stoppt, das Gesetz '
            'abzuschaffen.',
      ),
    ),
  ];
  for (final brightness in Brightness.values) {
    testWidgets(
      'bundle, front, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-bundle-front-${brightness.name}',
        brightness: brightness,
        pool: bundlePool,
      ),
    );
    testWidgets(
      'bundle, back, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-bundle-back-${brightness.name}',
        brightness: brightness,
        pool: bundlePool,
        act: (t) => t.tap(find.byType(ActionCard).last),
      ),
    );
    testWidgets(
      'bundle, one option done, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-bundle-one-done-${brightness.name}',
        brightness: brightness,
        pool: bundlePool,
        doneActions: [
          ActionLogEntry.fromOpportunity(
            bundlePool.first,
            doneAt: _in(-1),
            via: ActionVia.inAppBrowser,
          ),
        ],
        act: (t) => t.tap(find.byType(ActionCard).last),
      ),
    );
  }
  // Throwing a card away: a long press on [from], carried [share] of the
  // way to the trash can and held there; or let go there with [drop].
  final trash = find.byWidgetPredicate(
    (w) => w is Icon && w.semanticLabel == 'Papierkorb',
  );
  Future<void> carry(
    WidgetTester t, {
    Offset from = const Offset(195, 300),
    double share = 1,
    bool drop = false,
  }) async {
    final gesture = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(MiMotion.quick);
    final to = Offset.lerp(from, t.getCenter(trash), share)!;
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 12)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pump(MiMotion.quick);
    if (drop) {
      await gesture.up();
    } else {
      addTearDown(gesture.up);
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'throw hint, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-throw-hint-${brightness.name}',
        brightness: brightness,
        settle: false,
        // The lift at its highest.
        act: (t) => t.pump(const Duration(milliseconds: 1235)),
      ),
    );
    testWidgets(
      'card lifted, on its way, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-throw-carry-${brightness.name}',
        brightness: brightness,
        settle: false,
        act: (t) async {
          await t.pumpAndSettle();
          await carry(t, share: 0.45);
        },
      ),
    );
    testWidgets(
      'card over the trash, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-throw-hot-${brightness.name}',
        brightness: brightness,
        settle: false,
        act: (t) async {
          await t.pumpAndSettle();
          await carry(t);
        },
      ),
    );
    testWidgets(
      'reason sheet, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-throw-reasons-${brightness.name}',
        brightness: brightness,
        act: (t) => carry(t, drop: true),
      ),
    );
    testWidgets(
      'feedback sheet, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-feedback-sheet-${brightness.name}',
        brightness: brightness,
        act: (t) async {
          await t.tap(find.byIcon(Icons.person_outline));
          await t.pumpAndSettle();
          await t.ensureVisible(find.byKey(const ValueKey('row-feedback')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('row-feedback')));
          await t.pumpAndSettle();
          await t.tap(find.text('Fehler'));
          await t.enterText(
            find.byType(TextField),
            'Beim Zurückkommen aus dem Browser war die Karte kurz weg.',
          );
        },
      ),
    );
  }
  testWidgets(
    'back lifted, dark',
    (t) => shoot(
      t,
      'phone-throw-carry-back-dark',
      settle: false,
      act: (t) async {
        await t.pumpAndSettle();
        await t.tap(find.textContaining('Blitzer'));
        await t.pumpAndSettle();
        await carry(
          t,
          from: t.getCenter(find.text('Dafür spricht')),
          share: 0.45,
        );
      },
    ),
  );
  testWidgets(
    'reason with a note, dark',
    (t) => shoot(
      t,
      'phone-throw-note-dark',
      act: (t) async {
        await carry(t, drop: true);
        await t.pumpAndSettle();
        await t.tap(find.text('Möchte ich nicht unterstützen'));
        await t.pumpAndSettle();
        await t.enterText(
          find.byType(TextField),
          'Blitzer bringen nichts, lieber Schwellen.',
        );
      },
    ),
  );
  testWidgets(
    'all actions, dark',
    (t) => shoot(
      t,
      'phone-all-dark',
      act: (t) => t.tap(find.text('Alle 7 ansehen')),
    ),
  );
  testWidgets(
    'all actions, light',
    (t) => shoot(
      t,
      'phone-all-light',
      brightness: Brightness.light,
      act: (t) => t.tap(find.text('Alle 7 ansehen')),
    ),
  );
  testWidgets(
    'empty, dark',
    (t) => shoot(t, 'phone-empty-dark', pool: const []),
  );
  testWidgets(
    'font scale 1.3, dark',
    (t) => shoot(t, 'phone-hand-scale130-dark', textScale: 1.3),
  );

  // The pitch set: dark phones on light slides, at full phone resolution.
  Future<void> pitch(
    WidgetTester tester,
    String name, {
    Future<void> Function(WidgetTester tester)? act,
  }) =>
      shoot(
        tester,
        'pitch-$name',
        pixelRatio: 3,
        profile: _pitchProfile,
        doneActions: _pitchDone(),
        news: _pitchNews(),
        act: act,
      );

  // A screen of its own (onboarding, letter) on the app's themes.
  Future<void> screen(
    WidgetTester tester,
    String name,
    Widget home, {
    Brightness brightness = Brightness.dark,
    Future<void> Function(WidgetTester tester)? act,
    // False to catch an animation midway.
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    debugDisableShadows = false;
    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: miTheme(Brightness.light),
          darkTheme: miTheme(Brightness.dark),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (act != null) {
      await act(tester);
      if (settle) await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final boundary = _boundary.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_out/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
    debugDisableShadows = true;
  }

  Future<void> answer(WidgetTester t) async {
    // Leaning a little towards the left-hand statement.
    final track = t.getRect(find.byKey(const ValueKey('werte-track')));
    await t.tapAt(Offset(track.left + track.width * 0.3, track.center.dy));
  }

  // Answers anywhere along the slider, not only whole steps.
  const someAnswers = {
    'wirtschaft_gleichheit': -1.4,
    'wirtschaft_staat': 0.6,
    'diplomatie_nation': 0.85,
    'diplomatie_welt': 1.7,
    'freiheit_staat': -0.4,
    'freiheit_sicherheit': 0.0,
    'wandel_tradition': 1.2,
    'wandel_zukunft': -0.9,
  };

  for (final brightness in Brightness.values) {
    testWidgets(
      'questionnaire, ${brightness.name}',
      (t) => screen(
        t,
        'phone-werte-${brightness.name}',
        ValueProfileScreen(onComplete: (_) {}),
        brightness: brightness,
      ),
    );
    testWidgets(
      'questionnaire under way, ${brightness.name}',
      (t) => screen(
        t,
        'phone-werte-mid-${brightness.name}',
        ValueProfileScreen(
          onComplete: (_) {},
          initial: Map.fromEntries(someAnswers.entries.take(2)),
        ),
        brightness: brightness,
        act: (t) async {
          for (var i = 0; i < 2; i++) {
            await t.tap(find.text('Weiter'));
            await t.pumpAndSettle();
          }
          await answer(t);
        },
      ),
    );
    testWidgets(
      'picture revealed, ${brightness.name}',
      (t) => screen(
        t,
        'phone-werte-bild-${brightness.name}',
        ValueProfileScreen(onComplete: (_) {}, initial: someAnswers),
        brightness: brightness,
        act: (t) async {
          for (var i = 0; i < 7; i++) {
            await t.tap(find.text('Weiter'));
            await t.pumpAndSettle();
          }
          await t.tap(find.text('Fertig'));
        },
      ),
    );
    RucksackScreen rucksack() => RucksackScreen(
          werte: someAnswers,
          onComplete: (_) {},
          // As the Bundestag's data has 01067: Dresden I only.
          onLocate: (_) async => const PlzLookup(
            home: HomeLocation(kreis: '14612', lat: 51.05, lon: 13.73),
            wahlkreise: [
              MdbOption(
                wahlkreisNr: 158,
                wahlkreisName: 'Dresden I',
                mdbName: 'Jana Beispiel',
                mdbParty: 'Partei A',
              ),
            ],
          ),
        );
    testWidgets(
      'rucksack, where you live, empty, ${brightness.name}',
      (t) => screen(
        t,
        'phone-rucksack-plz-empty-${brightness.name}',
        rucksack(),
        brightness: brightness,
      ),
    );
    testWidgets(
      'rucksack, where you live, ${brightness.name}',
      (t) => screen(
        t,
        'phone-rucksack-plz-${brightness.name}',
        rucksack(),
        brightness: brightness,
        act: (t) async {
          await t.enterText(find.byType(TextField).first, '01067');
        },
      ),
    );
    testWidgets(
      'rucksack, no local topics yet, ${brightness.name}',
      (t) => screen(
        t,
        'phone-rucksack-plz-no-local-${brightness.name}',
        RucksackScreen(
          werte: someAnswers,
          onComplete: (_) {},
          onLocate: (_) async => const PlzLookup(
            home: HomeLocation(kreis: '09162', lat: 48.14, lon: 11.57),
            wahlkreise: [
              MdbOption(
                wahlkreisNr: 218,
                wahlkreisName: 'München-Süd',
                mdbName: 'Jana Beispiel',
                mdbParty: 'Partei A',
              ),
            ],
            coverage: LocalCoverage.none,
          ),
        ),
        brightness: brightness,
        act: (t) async {
          await t.enterText(find.byType(TextField).first, '80331');
        },
      ),
    );
    testWidgets(
      'rucksack, unknown PLZ, ${brightness.name}',
      (t) => screen(
        t,
        'phone-rucksack-plz-unknown-${brightness.name}',
        RucksackScreen(
          werte: someAnswers,
          onComplete: (_) {},
          onLocate: (_) async => null,
        ),
        brightness: brightness,
        act: (t) async {
          await t.enterText(find.byType(TextField).first, '09999');
        },
      ),
    );
    testWidgets(
      'rucksack, packed, ${brightness.name}',
      (t) => screen(
        t,
        'phone-rucksack-${brightness.name}',
        rucksack(),
        brightness: brightness,
        act: (t) async {
          await t.enterText(find.byType(TextField).first, '01067');
          await t.pumpAndSettle();
          await t.tap(find.text('Weiter'));
          await t.pumpAndSettle();
          for (final label in ['Mieter:in', 'Auf Wohnungssuche']) {
            await t.tap(find.text(label));
            await t.pumpAndSettle();
          }
          // On to Gesundheit, all of it private.
          for (var i = 0; i < 3; i++) {
            await t.fling(find.byType(PageView), const Offset(-300, 0), 1000);
            await t.pumpAndSettle();
          }
          await t.tap(find.textContaining('Chronisch krank'));
        },
      ),
    );
    testWidgets(
      'letter, ${brightness.name}',
      (t) => screen(
        t,
        'phone-letter-${brightness.name}',
        LetterScreen(
          opportunity: _opportunities()[3],
          repository: _Pool(const []),
          onViewPaper: () {},
        ),
        brightness: brightness,
        act: (t) async {
          await t.enterText(
            find.byType(TextField),
            'Meine Mutter geht dort zur Ärztin und kann nicht weit laufen.',
          );
          await t.ensureVisible(find.text('Brief erstellen'));
          await t.pumpAndSettle();
          await t.tap(find.text('Brief erstellen'));
          await t.pumpAndSettle();
          await t.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -500),
          );
        },
      ),
    );
  }
  testWidgets(
    'letter before drafting, dark',
    (t) => screen(
      t,
      'phone-letter-start-dark',
      LetterScreen(
        opportunity: _opportunities()[3],
        repository: _Pool(const []),
        onViewPaper: () {},
      ),
    ),
  );

  testWidgets('pitch 1, hand', (t) => pitch(t, '1-hand'));
  testWidgets(
    'pitch 2, card back',
    (t) =>
        pitch(t, '2-back', act: (t) => t.tap(find.textContaining('Blitzer'))),
  );
  testWidgets(
    'pitch 3, impact',
    (t) => pitch(
      t,
      '3-impact',
      act: (t) async {
        await t.tap(find.text('Mein Impact'));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Folgen').first);
      },
    ),
  );
  testWidgets(
    'pitch 4, profile',
    (t) => pitch(t, '4-profile', act: (t) => t.tap(find.text('Mein Profil'))),
  );
  for (final brightness in Brightness.values) {
    // Days back to this week's Monday, so the states hold on any weekday.
    final monday = _now.weekday - 1;
    for (final (name, history) in [
      ('strong', _flameHistory(daysAgo: 0)),
      // Last week's Monday: still running, at least a week ago.
      ('ember', _flameHistory(daysAgo: monday + 7)),
      // The week before last: one week missed, paused.
      ('smoke', _flameHistory(daysAgo: monday + 10)),
    ]) {
      testWidgets(
        'flame $name, ${brightness.name}',
        (t) => shoot(
          t,
          'phone-flame-$name-${brightness.name}',
          brightness: brightness,
          doneActions: history,
        ),
      );
      testWidgets(
        'streak details $name, ${brightness.name}',
        (t) => shoot(
          t,
          'phone-streak-$name-${brightness.name}',
          brightness: brightness,
          doneActions: history,
          act: (t) => t.tap(find.byType(StreakFlame)),
        ),
      );
    }
    testWidgets(
      'profile badges, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-profile-badges-${brightness.name}',
        brightness: brightness,
        profile: _pitchProfile,
        doneActions: _playedHistory(),
        act: (t) async {
          await t.tap(find.text('Mein Profil'));
          await t.pumpAndSettle();
          await t.drag(
            find.byType(Scrollable).first,
            const Offset(0, -400),
          );
        },
      ),
    );
    testWidgets(
      'profile, no badges yet, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-profile-nobadges-${brightness.name}',
        brightness: brightness,
        profile: _pitchProfile,
        act: (t) async {
          await t.tap(find.text('Mein Profil'));
          await t.pumpAndSettle();
          await t.drag(
            find.byType(Scrollable).first,
            const Offset(0, -400),
          );
        },
      ),
    );
    testWidgets(
      'all badges, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-badges-${brightness.name}',
        brightness: brightness,
        profile: _pitchProfile,
        doneActions: _playedHistory(),
        act: (t) async {
          await t.tap(find.text('Mein Profil'));
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byKey(const ValueKey('row-badges')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await t.tap(find.byKey(const ValueKey('row-badges')));
        },
      ),
    );
    final cards = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_DealtCard',
    );
    testWidgets(
      'reveal, face down, ${brightness.name}',
      (t) => screen(
        t,
        'phone-reveal-down-${brightness.name}',
        brightness: brightness,
        _MomentLauncher(_playedHistory()),
        act: (t) => t.tap(find.text('show')),
      ),
    );
    testWidgets(
      'reveal, mid turn, ${brightness.name}',
      (t) => screen(
        t,
        'phone-reveal-mid-${brightness.name}',
        brightness: brightness,
        _MomentLauncher(_playedHistory()),
        settle: false,
        act: (t) async {
          await t.tap(find.text('show'));
          await t.pumpAndSettle();
          await t.tap(cards.first);
          // The first frame starts the turn's clock.
          await t.pump();
          await t.pump(const Duration(milliseconds: 560));
        },
      ),
    );
    testWidgets(
      'reveal, all turned, ${brightness.name}',
      (t) => screen(
        t,
        'phone-reveal-up-${brightness.name}',
        brightness: brightness,
        _MomentLauncher(_playedHistory().take(7).toList()),
        act: (t) async {
          await t.tap(find.text('show'));
          await t.pumpAndSettle();
          await t.tap(cards.first);
          await t.pumpAndSettle();
          await t.tap(cards.last);
        },
      ),
    );
    testWidgets(
      'profile, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-profile-${brightness.name}',
        brightness: brightness,
        profile: _pitchProfile,
        act: (t) => t.tap(find.text('Mein Profil')),
      ),
    );
    testWidgets(
      'profile topics sheet, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-profile-themen-${brightness.name}',
        brightness: brightness,
        profile: _pitchProfile,
        act: (t) async {
          await t.tap(find.text('Mein Profil'));
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byKey(const ValueKey('row-themen')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await t.tap(find.byKey(const ValueKey('row-themen')));
        },
      ),
    );
    testWidgets(
      'profile turned over, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-profile-turned-${brightness.name}',
        brightness: brightness,
        profile: _pitchProfile,
        act: (t) async {
          await t.tap(find.text('Mein Profil'));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const ValueKey('wertebild')));
        },
      ),
    );
    testWidgets(
      'profile, lower half, ${brightness.name}',
      (t) => shoot(
        t,
        'phone-profile-lower-${brightness.name}',
        brightness: brightness,
        profile: _pitchProfile,
        act: (t) async {
          await t.tap(find.text('Mein Profil'));
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.text('Deine Themen'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
        },
      ),
    );
  }
}

final _pitchProfile = UserProfile(
  werte: const {
    'wirtschaft_gleichheit': 1,
    'wirtschaft_staat': 0,
    'diplomatie_nation': -1,
    'diplomatie_welt': 2,
    'freiheit_staat': 1,
    'freiheit_sicherheit': 0,
    'wandel_tradition': -1,
    'wandel_zukunft': 1,
  },
  plz: '01067',
  mdbWahlkreis: 'Dresden I',
  mdbName: 'Jana Beispiel',
  mdbParty: 'Partei',
  lebenslagen: const {'eltern', 'oepnv', 'mieter'},
  interests: InterestWeights(
    weights: const {
      'Mobilität/Verkehr': 0.7,
      'Familie/Kinder': 0.5,
      'Umwelt/Natur': 0.2,
    },
    asOf: DateTime.now(),
  ),
);

// Real actions and the reports the news dry run of 2026-11-11 judged
// relevant to them (backend/scripts/dryrun_output), oldest first.
List<ActionLogEntry> _pitchDone() => [
      ActionLogEntry(
        opportunityId: 'gewalt-kinder',
        doneAt: _in(-9),
        via: ActionVia.inAppBrowser,
        title: 'Aktionsplan gegen Gewalt an Kindern!',
        kind: OpportunityKind.petition,
        sourceOrg: 'WeAct',
        sourceUrl: 'https://weact.campact.de/petitions/'
            'aktionsplan-gegen-gewalt-an-kindern-jetzt',
        affectedTags: const ['Familie/Kinder'],
      ),
      ActionLogEntry(
        opportunityId: 'hilfsmittel',
        doneAt: _in(-5),
        via: ActionVia.inAppBrowser,
        title: 'Alarmstufe Rot: Individuelle Hilfsmittelversorgung sichern – '
            '3%-Pauschalabschlag streichen!',
        kind: OpportunityKind.petition,
        sourceOrg: 'openPetition',
        sourceUrl: 'https://www.openpetition.de/petition/online/'
            'alarmstufe-rot-individuelle-hilfsmittelversorgung-sichern-3-'
            'pauschalabschlag-streichen',
        affectedTags: const ['Gesundheit/Pflege'],
      ),
      ActionLogEntry(
        opportunityId: 'emissionshandel',
        doneAt: _in(-2),
        via: ActionVia.inAppBrowser,
        title: 'EU-Emissionshandelssystem (See- und Luftverkehr sowie '
            'ortsfeste Anlagen) und Marktstabilitätsreserve – Überprüfung',
        kind: OpportunityKind.consultation,
        sourceOrg: 'Europäische Kommission',
        sourceUrl: 'https://ec.europa.eu/info/law/better-regulation/'
            'have-your-say/initiatives/14549_de',
        affectedTags: const ['Umwelt/Natur', 'Mobilität/Verkehr'],
      ),
    ];

ImpactNewsFeed _pitchNews() => ImpactNewsFeed({
      'emissionshandel': ImpactNewsEntry(
        checkedAt: _now,
        items: [
          ImpactNewsItem(
            level: 'exact',
            kind: 'news',
            title: 'Merz hält am EU-Emissionshandel fest, Kommission will '
                'Luftverkehr 2029 einbeziehen',
            url: 'https://www.airliners.de/merz-haelt-eu-emissionshandel-fest-'
                'kommission-will-luftverkehr-2029-einbeziehen/91455',
            snippet: 'Kanzler Merz bekennt sich zum EU-Emissionshandel. Die '
                'Kommission will das ETS ab 2029 auf Flüge zu den '
                'Golf-Drehkreuzen und nach Istanbul ausweiten.',
            publishedOn: DateTime(2026, 11, 11),
          ),
          ImpactNewsItem(
            level: 'exact',
            kind: 'news',
            title: 'ICAO-Ratsvorsitzender kritisiert EU-Pläne für '
                'Airline-Emissionshandel',
            url: 'https://www.dvz.de/politik/detail/news/icao-ratsvorsitzender-'
                'kritisiert-eu-plaene-fuer-airline-emissionshandel.html',
            snippet: 'Die EU-Kommission spürt internationalen Gegenwind für '
                'ihren Vorschlag, den Luftverkehr-Emissionshandel über '
                'Europas Grenzen hinaus auszudehnen.',
            publishedOn: DateTime(2026, 10, 19),
          ),
          ImpactNewsItem(
            level: 'exact',
            kind: 'news',
            title:
                'Airlines gegen EU-Pläne für erweiterten CO2-Emissionshandel',
            url: 'https://www.news.at/ausflugsziele/airlines-gegen-eu-plane-'
                'fur-erweiterten-co2-emissionshandel',
            snippet: 'Die EU-Kommission hat vorgeschlagen, den Emissionshandel '
                'auf Flüge aus der EU in andere Regionen auszuweiten.',
            publishedOn: DateTime(2026, 10, 8),
          ),
        ],
      ),
      'hilfsmittel': ImpactNewsEntry(
        checkedAt: _now,
        items: [
          ImpactNewsItem(
            level: 'issue',
            kind: 'statement',
            title: 'GKV-BStabG zerstört die Hilfsmittelversorgungsstrukturen '
                'in Deutschland',
            url: 'https://www.ord.de/unternehmen/beitraege/gkv-bstabg-'
                'zerstoert-die-hilfsmittelversorgungsstrukturen-in-deutschland',
            snippet: 'Der Hilfsmittelbereich gehört nicht zu den '
                'Kostentreibern der gesetzlichen Krankenversicherungen!',
            publishedOn: DateTime(2026, 6, 3),
          ),
          ImpactNewsItem(
            level: 'exact',
            kind: 'news',
            title: 'Korrekturgesetz: Die Koalition ändert das Sparpaket',
            url: 'https://www.aok.de/pp/gg/gesundheitssystem/'
                'korrekturgesetz-sparpaket',
            snippet: 'Im Bereich der Hilfsmittelversorgung hat die '
                'schwarz-rote Koalition einen pauschalen Abschlag auf alle '
                'vertraglich vereinbarten Preise für Hilfsmittel eingeführt.',
            publishedOn: DateTime(2026, 6, 10),
          ),
        ],
      ),
      'gewalt-kinder': ImpactNewsEntry(
        checkedAt: _now,
        items: [
          ImpactNewsItem(
            level: 'exact',
            kind: 'social',
            title: 'Gewalt an Kindern: Wo bleibt der Aufschrei?',
            url: 'https://www.campact.de/blog/'
                'gewalt-an-kindern-weact-petition-statistik',
            snippet: '',
            publishedOn: DateTime(2026, 10, 2),
          ),
        ],
      ),
    });

// Palette alternatives, rendered side by side on the same hand. Each keeps
// ink text readable on its four faces.
final _palettes = <String, (Color table, Color stock, List<Color> faces)>{
  'A  Jetzt': (
    const Color(0xFF101820),
    const Color(0xFFF4F1EA),
    const [
      Color(0xFFFF5A5F),
      Color(0xFF2EC4B6),
      Color(0xFFFFBF3C),
      Color(0xFF8C84FF),
    ],
  ),
  'B  Riso': (
    const Color(0xFF0E0E10),
    const Color(0xFFFFFFFF),
    const [
      Color(0xFFFF6FC4),
      Color(0xFF4FA8FF),
      Color(0xFFFFE600),
      Color(0xFF2FD88A),
    ],
  ),
  'C  Primär': (
    const Color(0xFF1A1A1A),
    const Color(0xFFF2EFE8),
    const [
      Color(0xFFF25C4B),
      Color(0xFF6C9BFF),
      Color(0xFFF6C21C),
      Color(0xFF57D9A3),
    ],
  ),
  'D  Pastell': (
    const Color(0xFF1B1F3A),
    const Color(0xFFF7F5F0),
    const [
      Color(0xFFFFB3A7),
      Color(0xFFA7E3D9),
      Color(0xFFFFE29A),
      Color(0xFFC9C2FF),
    ],
  ),
};

Future<void> _shootPalettes(WidgetTester tester, Brightness brightness) async {
  const phone = Size(390, 760);
  // Four phones, a 20dp gap after each, 20dp padding around.
  tester.view.physicalSize =
      Size(phone.width * 4 + 20 * 4 + 40, phone.height + 40) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  debugDisableShadows = false;
  final base = miTheme(brightness);
  final light = brightness == Brightness.light;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ColoredBox(
          color: const Color(0xFF777777),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                for (final MapEntry(key: name, value: (table, stock, faces))
                    in _palettes.entries) ...[
                  SizedBox.fromSize(
                    size: phone,
                    child: Theme(
                      data: base.copyWith(
                        scaffoldBackgroundColor: table,
                        extensions: [
                          (light ? MiColors.light : MiColors.dark).copyWith(
                            table: light ? null : table,
                            onTable: light ? table : null,
                            onCard: table,
                            cardStock: stock,
                            topics: faces,
                          ),
                        ],
                      ),
                      child: Builder(
                        builder: (context) => Scaffold(
                          backgroundColor: context.mi.table,
                          appBar: AppBar(
                            backgroundColor: context.mi.table,
                            foregroundColor: context.mi.onTable,
                            title: Text(name),
                          ),
                          body: AktionenTab(
                            opportunityRepository: _Pool(_opportunities()),
                            profile: const UserProfile(
                              lebenslagen: {'eltern', 'oepnv', 'mieter'},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_out/palettes-${brightness.name}.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load('Unbounded', [
    'assets/fonts/Unbounded-Bold.ttf',
    'assets/fonts/Unbounded-ExtraBold.ttf',
  ]);
  await load('AlbertSans', [
    'assets/fonts/AlbertSans-Medium.ttf',
    'assets/fonts/AlbertSans-SemiBold.ttf',
    'assets/fonts/AlbertSans-Bold.ttf',
    'assets/fonts/AlbertSans-ExtraBold.ttf',
  ]);
  // The legacy tabs and system widgets fall back to Roboto.
  final root = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)),
    );
  await icons.load();
}

final _now = DateTime.now();
DateTime _in(int days) => DateTime(_now.year, _now.month, _now.day + days);

// Ten actions over six weeks with a week's pause, oldest first. The tenth
// is the week's first: milestone, Wohnen's first badge and the streak at
// once. The seventh gives Familie and Mobilität their first.
List<ActionLogEntry> _playedHistory() {
  final week = _now.weekday - 1;
  final plan = <(int, List<String>)>[
    (-week - 35, ['Umwelt/Natur', 'Familie/Kinder']),
    (-week - 34, ['Umwelt/Natur']),
    (-week - 28, ['Umwelt/Natur', 'Mobilität/Verkehr']),
    (-week - 27, ['Familie/Kinder', 'Wohnen/Miete']),
    (-week - 21, ['Umwelt/Natur', 'Mobilität/Verkehr']),
    (-week - 20, ['Wohnen/Miete']),
    (-week - 7, ['Umwelt/Natur', 'Familie/Kinder', 'Mobilität/Verkehr']),
    (-week - 6, ['Umwelt/Natur', 'Gesundheit/Pflege']),
    (-week - 2, ['Umwelt/Natur', 'Mobilität/Verkehr']),
    (-week, ['Umwelt/Natur', 'Wohnen/Miete']),
  ];
  return [
    for (final (i, (day, tags)) in plan.indexed)
      ActionLogEntry(
        opportunityId: 'played-$i',
        doneAt: _in(day).add(const Duration(hours: 10)),
        via: ActionVia.inAppBrowser,
        title: 'Aktion $i',
        kind: OpportunityKind.petition,
        sourceOrg: 'openPetition',
        sourceUrl: 'https://example.org/$i',
        affectedTags: tags,
      ),
  ];
}

// Three weeks in a row, the last action [daysAgo] days ago.
List<ActionLogEntry> _flameHistory({required int daysAgo}) => [
      for (final (i, days) in [daysAgo + 14, daysAgo + 7, daysAgo].indexed)
        ActionLogEntry(
          opportunityId: 'flame-$i',
          doneAt: _in(-days).add(const Duration(hours: 10)),
          via: ActionVia.inAppBrowser,
          title: 'Aktion $i',
          kind: OpportunityKind.petition,
          sourceOrg: 'openPetition',
          sourceUrl: 'https://example.org/$i',
          affectedTags: const ['Umwelt/Natur'],
        ),
    ];

// Shows the moment the last of [log] brought, as after its "Fertig".
class _MomentLauncher extends StatelessWidget {
  const _MomentLauncher(this.log);

  final List<ActionLogEntry> log;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final moment = ProgressMoment.between(
      Progress.of(ActionLog(log.sublist(0, log.length - 1)), now),
      Progress.of(ActionLog(log), now),
    )!;
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showProgressMoment(context, moment),
          child: const Text('show'),
        ),
      ),
    );
  }
}

List<Opportunity> _opportunities() => [
      _o(
        'kita',
        kind: OpportunityKind.petition,
        source: 'openPetition',
        title: 'Sollen Blitzer vor Kitas und Schulen kommen?',
        summary: 'Eine Petition fordert feste Blitzer vor allen Dresdner '
            'Kitas und Grundschulen, damit Autos dort Tempo 30 einhalten.',
        tags: ['Familie/Kinder', 'Sicherheit'],
        snippets: {
          'hat_kinder:true':
              'Dein Kind ist auf dem Schulweg sicherer, wenn Autos dort '
                  'langsamer fahren.',
        },
        closes: 12,
        support: 1840,
        goal: 2500,
        pro: ['Weniger Unfälle auf Schulwegen', 'Tempo 30 wird ernst genommen'],
        contra: ['Kosten für Anschaffung und Betrieb', 'Gilt als Abzocke'],
      ),
      _o(
        'bahnhof',
        kind: OpportunityKind.publicDisplay,
        source: 'Beteiligungsportal Sachsen',
        title: 'Wie wird der Alte Leipziger Bahnhof in Neustadt bebaut?',
        summary: 'Die Stadt legt den Bebauungsplan für das Gelände am Alten '
            'Leipziger Bahnhof aus. Bis zum Ende der Frist kann jede:r '
            'Hinweise geben.',
        tags: ['Stadtentwicklung/Bauen', 'Mobilität/Verkehr'],
        snippets: {
          'oepnv_nutzung:true':
              'Du fährst Bus und Bahn – auf dem Gelände ist eine neue '
                  'Haltestelle geplant.',
        },
        closes: 3,
        lebenslagen: ['oepnv'],
      ),
      _o(
        'wohngeld',
        kind: OpportunityKind.consultation,
        source: 'Beteiligungsportal Sachsen',
        title: 'Drohen Kürzungen beim Wohngeld?',
        summary: 'Das Land fragt, wie die Wohngeldstellen künftig arbeiten '
            'sollen und wo gespart werden kann.',
        tags: ['Wohnen/Miete'],
        snippets: {
          'wohnsituation:mieter':
              'Als Mieter:in kann sich ändern, wie viel Wohngeld du '
                  'bekommst.',
        },
        closes: 24,
      ),
      _o(
        'gruna',
        kind: OpportunityKind.decision,
        source: 'Ratsinformationssystem Dresden',
        title: 'Sollen die Parkplätze am Ärztehaus und der Apotheke in '
            'Dresden-Gruna erhalten oder neu eingerichtet werden?',
        summary: 'Der Ortsbeirat Blasewitz entscheidet, ob die Stellplätze '
            'vor dem Ärztehaus bleiben.',
        tags: ['Mobilität/Verkehr', 'Gesundheit/Pflege'],
        closes: 6,
        lebenslagen: ['oepnv'],
      ),
      _o(
        'mecfs',
        kind: OpportunityKind.petition,
        source: 'WeAct',
        title: 'Bekommen ME/CFS-Betroffene genug Hilfe?',
        summary: 'Eine Petition fordert mehr Forschung und Versorgung für '
            'Menschen mit ME/CFS.',
        tags: ['Gesundheit/Pflege'],
        closes: 40,
        support: 52310,
      ),
      _o(
        'opensource',
        kind: OpportunityKind.survey,
        source: 'EU-Kommission: Ihre Meinung zählt',
        title: 'Soll Open-Source-Arbeit als Ehrenamt gelten?',
        summary: 'Die EU fragt, wie freiwillige Arbeit an offener Software '
            'anerkannt werden soll.',
        tags: ['Digitales/Datenschutz'],
        announced: true,
        opens: 20,
      ),
      _o(
        'pflege',
        kind: OpportunityKind.consultation,
        source: 'EU-Kommission: Ihre Meinung zählt',
        title: 'Darf die Pflege für Angehörige teurer werden?',
        summary: 'Die EU-Kommission sammelt Meinungen zur Finanzierung der '
            'Langzeitpflege.',
        tags: ['Rente/Alter'],
        closes: 31,
      ),
    ];

Opportunity _o(
  String id, {
  required OpportunityKind kind,
  required String source,
  required String title,
  required String summary,
  required List<String> tags,
  Map<String, String> snippets = const {},
  List<String> lebenslagen = const [],
  List<String> pro = const [],
  List<String> contra = const [],
  int? closes,
  int? opens,
  int? support,
  int? goal,
  bool announced = false,
  OpportunityBundle? bundle,
}) =>
    Opportunity(
      bundle: bundle,
      id: id,
      sourceOrg: source,
      sourceUrl: 'https://example.org/$id',
      kind: kind,
      isAnnounced: announced,
      region: 'dresden',
      title: title,
      summary: summary,
      affectedTags: tags,
      lebenslagen: lebenslagen,
      werteRelevanz: const {},
      proArgumente: pro,
      contraArgumente: contra,
      personalImpactSnippets: snippets,
      opensOn: opens == null ? null : _in(opens),
      closesOn: closes == null ? null : _in(closes),
      supportCount: support,
      supportGoal: goal,
      everydayRelevance: 4,
      accessibility: 4,
      firstSeenAt: _in(-2),
    );

class _Pool implements OpportunityRepository {
  _Pool(this.items, [this.news = const ImpactNewsFeed()]);

  final List<Opportunity> items;
  final ImpactNewsFeed news;

  @override
  Future<List<Opportunity>> pool({String? kreis}) async => items;

  @override
  Future<PlzLookup?> locate(String plz) async => null;

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) =>
      Stream.fromIterable([
        'Sehr geehrte Damen und Herren,\n\n',
        'am Ärztehaus in Gruna parken viele, die nicht weit laufen können, '
            'darunter meine Mutter. Bitte stimmen Sie dafür, die '
            'Stellplätze vor dem Ärztehaus und der Apotheke zu erhalten.\n\n',
        'Mit freundlichen Grüßen\n',
      ]);

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      const LetterRecipients(
        bodies: ['Stadtbezirksbeirat Blasewitz'],
        members: [
          CouncilMember(name: 'Anton Amsel', fraktion: 'CDU-Fraktion'),
          CouncilMember(name: 'Bea Berg', fraktion: 'Grüne-Fraktion'),
        ],
        offices: [
          FraktionOffice(
            fraktion: 'CDU-Fraktion',
            email: 'cdu-fraktion@dresden.de',
          ),
          FraktionOffice(
            fraktion: 'Grüne-Fraktion',
            email: 'gruene-fraktion@dresden.de',
          ),
          FraktionOffice(fraktion: 'Neue Fraktion'),
        ],
      );

  @override
  Future<void> markTracked(String opportunityId) async {}

  @override
  Future<ImpactNewsFeed> impactNews() async => news;
}
