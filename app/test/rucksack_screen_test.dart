import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/onboarding/rucksack/rucksack_screen.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    void Function(UserProfile) onComplete, {
    Future<List<MdbOption>> Function(String)? lookup,
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
          onLookupMdb: lookup ??
              (_) async => const [
                    MdbOption(
                      wahlkreisNr: 159,
                      wahlkreisName: 'Dresden I',
                      mdbName: 'Jana Beispiel',
                      mdbParty: 'Partei A',
                    ),
                  ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('asks where you live first, then packs Lebenslagen',
      (tester) async {
    UserProfile? result;
    await pump(tester, (p) => result = p);

    expect(find.text('Wo bist du zuhause?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '01067');
    await tester.pumpAndSettle();
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
    expect(result!.mdbName, 'Jana Beispiel');
    expect(result!.mdbWahlkreis, 'Dresden I');
    expect(result!.lebenslagen, {'mieter'});
  });

  testWidgets('private ones go into the Privatfach', (tester) async {
    UserProfile? result;
    await pump(tester, (p) => result = p);
    await tester.tap(find.text('Überspringen'));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.textContaining('Chronisch krank'));
    await tester.pumpAndSettle();
    expect(find.text('0 ausgewählt · 1 im Privatfach'), findsOneWidget);

    await tester.tap(find.text('Fertig'));
    expect(result!.plz, isNull);
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
          onLookupMdb: (_) async => const [],
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
    expect(result!.lebenslagen, {'mieter', 'chronisch_krank'});
  });

  testWidgets('a given PLZ cannot be skipped away by accident', (tester) async {
    await pump(tester, (_) {});
    expect(find.text('Überspringen'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '01067');
    await tester.pumpAndSettle();
    expect(find.text('Überspringen'), findsNothing);
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
          onLookupMdb: (_) async => const [
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
          ],
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
          onLookupMdb: (_) async => const [],
          onBack: () => left = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Überspringen'));
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

  testWidgets('keeps the PLZ when no Wahlkreis is found', (tester) async {
    UserProfile? result;
    await pump(tester, (p) => result = p, lookup: (_) async => const []);

    await tester.enterText(find.byType(TextField), '99999');
    await tester.pumpAndSettle();
    expect(find.textContaining('Keinen Wahlkreis gefunden'), findsOneWidget);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fertig'));

    expect(result!.plz, '99999');
    expect(result!.mdbName, isNull);
  });
}
