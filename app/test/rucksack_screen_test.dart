import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/domain/home_location.dart';
import 'package:meinimpact/src/features/feed/domain/local_coverage.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/onboarding/rucksack/rucksack_screen.dart';

const _home = HomeLocation(kreis: '14612', lat: 51.05, lon: 13.73);

PlzLookup _found([List<MdbOption> wahlkreise = const []]) =>
    PlzLookup(home: _home, wahlkreise: wahlkreise);

void main() {
  Future<void> pump(
    WidgetTester tester,
    void Function(UserProfile) onComplete, {
    Future<PlzLookup?> Function(String)? locate,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: miTheme(Brightness.dark),
        home: RucksackScreen(
          werte: const {'wirtschaft_gleichheit': -1.2},
          onComplete: onComplete,
          onLocate: locate ??
              (_) async => _found(const [
                    MdbOption(
                      wahlkreisNr: 159,
                      wahlkreisName: 'Dresden I',
                      mdbName: 'Jana Beispiel',
                      mdbParty: 'Partei A',
                    ),
                  ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterPlz(WidgetTester tester, [String plz = '01067']) async {
    await tester.enterText(find.byType(TextField), plz);
    await tester.pumpAndSettle();
  }

  bool weiterEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, 'Weiter'))
      .enabled;

  testWidgets('asks where you live first, then packs Lebenslagen',
      (tester) async {
    UserProfile? result;
    await pump(tester, (p) => result = p);

    expect(find.text('Wo bist du zuhause?'), findsOneWidget);
    await enterPlz(tester);
    expect(find.text('Im Bundestag: Jana Beispiel, Partei A'), findsOneWidget);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Was gehört zu dir?'), findsOneWidget);
    expect(find.text('Noch nichts ausgewählt'), findsOneWidget);

    await tester.tap(find.text('Mieter:in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vermieter:in'));
    await tester.pumpAndSettle();
    expect(find.text('2 ausgewählt'), findsOneWidget);

    // Tapping the faint outline takes it out again.
    await tester.tap(find.text('Vermieter:in'));
    await tester.pumpAndSettle();
    expect(find.text('1 ausgewählt'), findsOneWidget);

    await tester.tap(find.text('Fertig'));
    expect(result!.plz, '01067');
    expect(result!.home?.kreis, '14612');
    expect(result!.mdbName, 'Jana Beispiel');
    expect(result!.mdbWahlkreis, 'Dresden I');
    expect(result!.lebenslagen, {'mieter'});
  });

  testWidgets('the PLZ is required: no skipping, Weiter waits for it',
      (tester) async {
    await pump(tester, (_) {});

    expect(find.text('Überspringen'), findsNothing);
    expect(weiterEnabled(tester), isFalse);
    await enterPlz(tester);
    expect(weiterEnabled(tester), isTrue);
  });

  testWidgets('says so when there are no topics from there yet',
      (tester) async {
    await pump(
      tester,
      (_) {},
      locate: (plz) async => plz == '80331'
          ? const PlzLookup(
              home: HomeLocation(kreis: '09162', lat: 48.14, lon: 11.57),
              coverage: LocalCoverage.none,
            )
          : _found(),
    );

    await enterPlz(tester, '80331');

    expect(find.text(LocalCoverage.none.note!), findsOneWidget);
    expect(weiterEnabled(tester), isTrue);

    // A covered PLZ takes the note away again.
    await enterPlz(tester, '01067');
    expect(find.text(LocalCoverage.none.note!), findsNothing);
  });

  testWidgets('an unknown PLZ cannot go in', (tester) async {
    await pump(tester, (_) {}, locate: (_) async => null);

    await enterPlz(tester, '99999');

    expect(
      find.text('Diese PLZ kennen wir nicht. Stimmt sie?'),
      findsOneWidget,
    );
    expect(weiterEnabled(tester), isFalse);
  });

  testWidgets('offline the PLZ still goes in, to be located later',
      (tester) async {
    UserProfile? result;
    await pump(
      tester,
      (p) => result = p,
      locate: (_) async => throw Exception('offline'),
    );

    await enterPlz(tester);
    expect(find.textContaining('Gerade keine Verbindung'), findsOneWidget);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig'));

    expect(result!.plz, '01067');
    expect(result!.home, isNull);
  });

  testWidgets('private ones go into the Privatfach', (tester) async {
    UserProfile? result;
    await pump(tester, (p) => result = p);
    await enterPlz(tester);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.textContaining('Chronisch krank'));
    await tester.pumpAndSettle();
    expect(find.text('0 ausgewählt · 1 im Privatfach'), findsOneWidget);

    await tester.tap(find.text('Fertig'));
    expect(result!.lebenslagen, {'chronisch_krank'});
  });

  testWidgets('re-packing starts from what was packed before', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    UserProfile? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: miTheme(Brightness.dark),
        home: RucksackScreen(
          initialPlz: '01067',
          initialLebenslagen: const {'mieter', 'chronisch_krank'},
          onComplete: (p) => result = p,
          onLocate: (_) async => _found(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '01067',
    );
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('1 ausgewählt · 1 im Privatfach'), findsOneWidget);

    await tester.tap(find.text('Fertig'));
    expect(result!.plz, '01067');
    expect(result!.home?.kreis, '14612');
    expect(result!.lebenslagen, {'mieter', 'chronisch_krank'});
  });

  testWidgets('re-packing picks the Wahlkreis chosen before', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    UserProfile? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: miTheme(Brightness.dark),
        home: RucksackScreen(
          initialPlz: '01067',
          initialWahlkreis: 'Dresden II – Bautzen II',
          onComplete: (p) => result = p,
          onLocate: (_) async => _found(const [
            MdbOption(
              wahlkreisNr: 159,
              wahlkreisName: 'Dresden I',
              mdbName: 'Jana Beispiel',
              mdbParty: 'Partei A',
            ),
            MdbOption(
              wahlkreisNr: 160,
              wahlkreisName: 'Dresden II – Bautzen II',
              mdbName: 'Tom Muster',
              mdbParty: 'Partei B',
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig'));
    expect(result!.mdbName, 'Tom Muster');
  });

  testWidgets('Back goes from the Lebenslagen to the PLZ, then out',
      (tester) async {
    var left = false;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: miTheme(Brightness.dark),
        home: RucksackScreen(
          onComplete: (_) {},
          onLocate: (_) async => _found(),
          onBack: () => left = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enterPlz(tester);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Was gehört zu dir?'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Wo bist du zuhause?'), findsOneWidget);
    expect(left, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(left, isTrue);
  });

  testWidgets('a PLZ without Bundestag data still locates', (tester) async {
    UserProfile? result;
    await pump(tester, (p) => result = p, locate: (_) async => _found());

    await enterPlz(tester);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig'));

    expect(result!.home?.kreis, '14612');
    expect(result!.mdbName, isNull);
  });
}
