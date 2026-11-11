import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/domain/interest_weights.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/feed/presentation/widgets/profile_column.dart';

void main() {
  testWidgets('values show both poles of every axis', (tester) async {
    await _pump(
      tester,
      const UserProfile(
        werte: {'wirtschaft_gleichheit': -2, 'diplomatie_welt': 1},
      ),
    );

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
    expect(find.text('Fragebogen erneut ausfüllen'), findsOneWidget);
  });

  testWidgets('without answers it says so', (tester) async {
    await _pump(tester, const UserProfile());

    expect(find.text('Noch nicht ausgefüllt.'), findsOneWidget);
    expect(find.text('Fragebogen ausfüllen'), findsOneWidget);
    expect(find.text('Umverteilung'), findsNothing);
  });

  testWidgets('only set topics show; all of them open in a sheet',
      (tester) async {
    InterestWeights? changed;
    await _pump(
      tester,
      const UserProfile(
        interests: InterestWeights(
          manual: {'Wohnen/Miete': InterestLevel.more},
        ),
      ),
      onInterestsChanged: (w) => changed = w,
    );

    expect(find.text('Wohnen/Miete · mehr'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-Umwelt/Natur')), findsNothing);

    await tester.tap(find.text('Anpassen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-Umwelt/Natur')).last);
    await tester.pumpAndSettle();

    expect(changed?.manual['Umwelt/Natur'], InterestLevel.more);
    // The sheet follows the change at once.
    expect(find.text('Umwelt/Natur · mehr'), findsOneWidget);
  });

  testWidgets('the Lebenslagen picker opens in a sheet', (tester) async {
    Set<String>? changed;
    await _pump(
      tester,
      const UserProfile(),
      onLebenslagenChanged: (ids) => changed = ids,
    );

    await tester.tap(find.text('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Was ist dir wichtig?'), findsOneWidget);

    await tester.tap(find.text('Mieter:in'));
    await tester.pumpAndSettle();
    expect(changed, isNotNull);
    expect(changed, isNotEmpty);
  });
}

Future<void> _pump(
  WidgetTester tester,
  UserProfile profile, {
  ValueChanged<InterestWeights>? onInterestsChanged,
  ValueChanged<Set<String>>? onLebenslagenChanged,
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
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
