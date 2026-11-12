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
    final track = tester.getRect(find.byKey(const ValueKey('werte-track')));
    await tester.tapAt(
      Offset(track.left + track.width * along, track.center.dy),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('answers anywhere along the slider, not only whole steps',
      (tester) async {
    Map<String, double>? result;
    await pump(tester, (w) => result = w);

    await tapTrack(tester, 0.3);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Überspringen'));
      await tester.pumpAndSettle();
    }
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
    // Skipped questions stay out.
    expect(result!.keys, ['wirtschaft_gleichheit']);
  });

  testWidgets('snaps to the centre close to it', (tester) async {
    Map<String, double>? result;
    await pump(tester, (w) => result = w);

    await tapTrack(tester, 0.51);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Überspringen'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));

    expect(result, {'wirtschaft_gleichheit': 0.0});
  });

  testWidgets('tapping a statement leans towards it', (tester) async {
    await pump(tester, (_) {});

    await tester.tap(find.textContaining('Wer Leistung bringt'));
    await tester.pumpAndSettle();

    expect(find.text('Eher das'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
  });

  testWidgets('nothing answered skips the picture', (tester) async {
    Map<String, double>? result;
    await pump(tester, (w) => result = w);

    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Überspringen'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    expect(result, isEmpty);
    expect(find.text('Dein Bild'), findsNothing);
  });

  testWidgets('re-doing starts from the earlier answers', (tester) async {
    Map<String, double>? result;
    await pump(
      tester,
      (w) => result = w,
      initial: const {'wirtschaft_staat': 1.25},
    );

    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));

    expect(result, {'wirtschaft_staat': 1.25});
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
