import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/widgets/profile_column.dart';

void main() {
  testWidgets('the picture shows no values until it is turned over',
      (tester) async {
    await _pump(
      tester,
      const UserProfile(
        werte: {'wirtschaft_gleichheit': -2, 'diplomatie_welt': 1},
      ),
    );

    expect(find.text('Zum Anzeigen tippen'), findsOneWidget);
    expect(find.text('Umverteilung'), findsNothing);
    expect(find.textContaining('Nr.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('wertebild')));
    await tester.pumpAndSettle();

    expect(find.text('Zum Verbergen tippen'), findsOneWidget);
    for (final pole in [
      'Umverteilung',
      'Freier Markt',
      'National',
      'International',
      'Bürgerrechte',
      'Sicherheit',
      'Bewahren',
      'Verändern',
    ]) {
      expect(find.text(pole), findsOneWidget);
    }
    expect(find.text('Neu malen'), findsOneWidget);
  });

  testWidgets('without answers it says so', (tester) async {
    await _pump(tester, const UserProfile());

    expect(find.text('Noch nicht ausgefüllt.'), findsOneWidget);
    expect(find.text('Fragebogen ausfüllen'), findsOneWidget);
    expect(find.text('Umverteilung'), findsNothing);
  });

  testWidgets('the topics row opens the topics to forget', (tester) async {
    InterestWeights? changed;
    await _pump(
      tester,
      UserProfile(
        interests: InterestWeights(
          weights: const {
            'Wohnen/Miete': 0.5,
            'Umwelt/Natur': 0.1,
            'Sicherheit': -0.5,
          },
          asOf: DateTime.now(),
        ),
      ),
      onInterestsChanged: (w) => changed = w,
    );

    // No summary on the row: the topics are in the sheet.
    expect(find.text('Wohnen/Miete'), findsNothing);
    expect(find.byKey(const ValueKey('topic-Wohnen/Miete')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('row-themen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('topic-Wohnen/Miete')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-Umwelt/Natur')), findsNothing);
    expect(find.byKey(const ValueKey('topic-Sicherheit')), findsNothing);

    await tester.tap(find.byTooltip('Wohnen/Miete vergessen'));
    await tester.pumpAndSettle();

    expect(changed?.weights.containsKey('Wohnen/Miete'), isFalse);
    expect(changed?.weights['Sicherheit'], closeTo(-0.5, 1e-3));
    // The sheet follows at once.
    expect(find.byKey(const ValueKey('topic-Wohnen/Miete')), findsNothing);
  });

  testWidgets('without favoured topics it says where they come from',
      (tester) async {
    await _pump(tester, const UserProfile());

    await tester.tap(find.byKey(const ValueKey('row-themen')));
    await tester.pumpAndSettle();
    expect(find.textContaining('öffnest und erledigst'), findsOneWidget);
  });

  testWidgets('rows carry only their names', (tester) async {
    await _pump(
      tester,
      const UserProfile(
        plz: '01067',
        mdbWahlkreis: 'Dresden I',
        lebenslagen: {'mieter', 'eltern'},
      ),
    );

    expect(find.text('Was zu dir gehört'), findsOneWidget);
    expect(find.text('Dein Stadthaushalt'), findsOneWidget);
    expect(find.text('Deine Themen'), findsOneWidget);
    expect(find.textContaining('01067'), findsNothing);
    expect(find.text('Noch nicht verteilt'), findsNothing);
  });

  testWidgets('without a Rucksack screen, the row opens the picker',
      (tester) async {
    Set<String>? changed;
    await _pump(
      tester,
      const UserProfile(),
      onLebenslagenChanged: (ids) => changed = ids,
    );

    await tester.tap(find.byKey(const ValueKey('row-rucksack')));
    await tester.pumpAndSettle();
    expect(find.text('Was ist dir wichtig?'), findsOneWidget);

    await tester.tap(find.text('Mieter:in'));
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(changed, isNotEmpty);
  });

  testWidgets('no appearance row without a way to change it', (tester) async {
    await _pump(tester, const UserProfile());

    expect(find.byKey(const ValueKey('row-darstellung')), findsNothing);
  });

  testWidgets('the appearance row picks light, dark or the phone',
      (tester) async {
    ThemeMode? chosen;
    await _pump(
      tester,
      const UserProfile(),
      onThemeModeChanged: (mode) => chosen = mode,
    );

    await tester.tap(find.byKey(const ValueKey('row-darstellung')));
    await tester.pumpAndSettle();
    expect(find.text('Wie Handy'), findsOneWidget);

    await tester.tap(find.text('Hell'));
    await tester.pumpAndSettle();

    expect(chosen, ThemeMode.light);
    // The sheet closes, so the app turns all at once.
    expect(find.byKey(const ValueKey('appearance-choice')), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  UserProfile profile, {
  ValueChanged<InterestWeights>? onInterestsChanged,
  ValueChanged<Set<String>>? onLebenslagenChanged,
  ValueChanged<ThemeMode>? onThemeModeChanged,
}) async {
  tester.view.physicalSize = const Size(412, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: miTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfileColumn(
            profile: profile,
            onEdit: () {},
            onLebenslagenChanged: onLebenslagenChanged ?? (_) {},
            onInterestsChanged: onInterestsChanged ?? (_) {},
            onThemeModeChanged: onThemeModeChanged,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
