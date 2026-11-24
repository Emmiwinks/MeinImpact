// Renders the start of onboarding (intro, consent) and the Stadthaushalt
// with the real fonts at phone size and writes PNGs to
// ../.impeccable/review/ for the design review. Not part of the normal
// suite: run with `flutter test test_screenshots`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/l10n/app_localizations.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/features/feed/presentation/widgets/profile_column.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/onboarding/consent_screen.dart';
import 'package:meinimpact/src/features/onboarding/intro_screen.dart';
import 'package:meinimpact/src/features/onboarding/stadthaushalt/stadthaushalt.dart';
import 'package:meinimpact/src/features/onboarding/stadthaushalt/stadthaushalt_screen.dart';

const _out = '../.impeccable/review';
final _boundary = GlobalKey();

const _taler = {
  'kinder_bildung': 6,
  'soziales': 4,
  'oepnv_rad': 3,
  'strassen': 1,
  'kultur': 1,
  'sport_freizeit': 2,
  'gruen_klima': 3,
};

void main() {
  setUpAll(_loadFonts);

  Future<void> screen(
    WidgetTester tester,
    String name,
    Widget home, {
    Brightness brightness = Brightness.dark,
    Future<void> Function(WidgetTester tester)? act,
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
      await tester.pumpAndSettle();
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

  Future<void> drop(WidgetTester t, Map<String, int> taler) async {
    for (var i = 0; i < haushaltToepfe.length; i++) {
      for (var k = 0; k < (taler[haushaltToepfe[i].id] ?? 0); k++) {
        await t.tap(find.byType(TopfGlas).at(i));
        await t.pump();
      }
    }
  }

  for (final brightness in Brightness.values) {
    final b = brightness.name;
    testWidgets(
      'intro, $b',
      (t) => screen(
        t,
        'phone-intro-$b',
        IntroScreen(onStart: () {}, onExample: () {}),
        brightness: brightness,
      ),
    );
    testWidgets(
      'consent, $b',
      (t) => screen(
        t,
        'phone-consent-$b',
        ConsentScreen(onAgree: () {}),
        brightness: brightness,
        act: brightness == Brightness.light
            ? (t) => t.tap(find.text('Ich bin mindestens 16 Jahre alt.'))
            : null,
      ),
    );
    testWidgets(
      'stadthaushalt under way, $b',
      (t) => screen(
        t,
        'phone-haushalt-$b',
        StadthaushaltScreen(onComplete: (_) {}),
        brightness: brightness,
        act: (t) => drop(t, const {
          'kinder_bildung': 3,
          'soziales': 2,
          'strassen': 1,
          'sport_freizeit': 1,
          'gruen_klima': 1,
        }),
      ),
    );
    testWidgets(
      'stadthaushalt spent, $b',
      (t) => screen(
        t,
        'phone-haushalt-full-$b',
        StadthaushaltScreen(onComplete: (_) {}, initial: _taler),
        brightness: brightness,
      ),
    );
    testWidgets(
      'stadthaushalt revealed, $b',
      (t) => screen(
        t,
        'phone-haushalt-bild-$b',
        StadthaushaltScreen(onComplete: (_) {}, initial: _taler),
        brightness: brightness,
        act: (t) => t.tap(find.text('Fertig')),
      ),
    );
    testWidgets(
      'profile section, $b',
      (t) => screen(
        t,
        'phone-profil-haushalt-$b',
        Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: MiSpace.lg),
              child: ProfileColumn(
                profile: const UserProfile(
                  lebenslagen: {'eltern', 'oepnv', 'mieter'},
                  plz: '01067',
                  prioritaeten: _taler,
                ),
                onEdit: () {},
                onEditPrioritaeten: () {},
                onLebenslagenChanged: (_) {},
                onInterestsChanged: (_) {},
              ),
            ),
          ),
        ),
        brightness: brightness,
        act: (t) => t.scrollUntilVisible(
          find.text('Dein Stadthaushalt'),
          200,
          scrollable: find.byType(Scrollable).first,
        ),
      ),
    );
  }
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
  final root = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)),
    );
  await icons.load();
}
