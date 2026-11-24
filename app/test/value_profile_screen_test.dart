import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/onboarding/value_profile_screen.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    void Function(Map<String, double>) onComplete, {
    Map<String, double> initial = const {},
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: miTheme(Brightness.dark),
        home: ValueProfileScreen(onComplete: onComplete, initial: initial),
      ),
    );
  }

  Future<void> tapTrack(WidgetTester tester, double along) async {
    // Long statements push the slider below the fold.
    await tester.ensureVisible(find.byKey(const ValueKey('werte-track')));
    await tester.pumpAndSettle();
    final track = tester.getRect(find.byKey(const ValueKey('werte-track')));
    await tester.tapAt(
      Offset(track.left + track.width * along, track.center.dy),
    );
    await tester.pumpAndSettle();
  }

  // Answers the remaining questions in the middle ("Beides gleich").
  Future<void> answerRest(WidgetTester tester, {int from = 1}) async {
    for (var i = from; i < werteQuestionKeys.length; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await tapTrack(tester, 0.5);
    }
  }

  testWidgets('answers anywhere along the slider, not only whole steps',
      (tester) async {
    Map<String, double>? result;
    await pump(tester, (w) => result = w);

    await tapTrack(tester, 0.3);
    await answerRest(tester);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    // The picture is framed before the answers go anywhere.
    expect(find.text('Dein Bild'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('Weiter'));
    final v = result!['wirtschaft_gleichheit']!;
    expect(v, lessThan(-0.5));
    expect(v, greaterThan(-1.5));
    expect(v, isNot(v.roundToDouble()));
    expect(result!.keys, werteQuestionKeys);
  });

  testWidgets('snaps to the centre close to it', (tester) async {
    Map<String, double>? result;
    await pump(tester, (w) => result = w);

    await tapTrack(tester, 0.51);
    await answerRest(tester);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));

    expect(result!['wirtschaft_gleichheit'], 0.0);
  });

  testWidgets('tapping a statement leans towards it', (tester) async {
    await pump(tester, (_) {});

    await tester.tap(find.textContaining('Wer Leistung bringt'));
    await tester.pumpAndSettle();

    expect(find.text('Eher das'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
  });

  testWidgets('there is no skipping: Weiter waits for an answer',
      (tester) async {
    await pump(tester, (_) {});

    expect(find.text('Überspringen'), findsNothing);
    final weiter = find.widgetWithText(FilledButton, 'Weiter');
    expect(tester.widget<FilledButton>(weiter).onPressed, isNull);

    await tapTrack(tester, 0.5);
    expect(tester.widget<FilledButton>(weiter).onPressed, isNotNull);
  });

  testWidgets('re-doing starts from the earlier answers', (tester) async {
    final earlier = {
      for (final (i, key) in werteQuestionKeys.indexed) key: i / 4 - 1,
    };
    Map<String, double>? result;
    await pump(tester, (w) => result = w, initial: earlier);

    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));

    expect(result, earlier);
  });

  testWidgets('Back steps through the questions, then cancels', (tester) async {
    var cancelled = false;
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: miTheme(Brightness.dark),
        home: ValueProfileScreen(
          onComplete: (_) {},
          onCancel: () => cancelled = true,
        ),
      ),
    );
    await tapTrack(tester, 0.5);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cancelled, isFalse);
    expect(find.textContaining('Der Staat sollte große Vermögen'), findsOne);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
  });

  test('profiles saved with whole steps still load', () {
    final profile = UserProfile.fromJson({
      'werte': {'wirtschaft_gleichheit': -2, 'wandel_zukunft': 0.75},
    });
    expect(
      profile.werte,
      {'wirtschaft_gleichheit': -2.0, 'wandel_zukunft': 0.75},
    );
    expect(werteQuestionKeys, hasLength(8));
  });
}
