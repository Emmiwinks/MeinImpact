import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/meinimpact_app.dart';
import 'package:meinimpact/src/app/theme/mi_theme.dart';
import 'package:meinimpact/src/core/profile/user_profile_store.dart';
import 'package:meinimpact/src/features/feed/domain/home_location.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';
import 'package:meinimpact/src/features/onboarding/stadthaushalt/stadthaushalt.dart';
import 'package:meinimpact/src/features/onboarding/stadthaushalt/stadthaushalt_screen.dart';
import 'package:meinimpact/src/features/tracking/data/action_log_store.dart';
import 'package:meinimpact/src/features/tracking/domain/action_log.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  FilledButton button(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

  group('Stadthaushalt', () {
    Future<void> pump(
      WidgetTester tester,
      void Function(Map<String, int>) onComplete, {
      Map<String, int> initial = const {},
    }) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: miTheme(Brightness.dark),
          home: StadthaushaltScreen(onComplete: onComplete, initial: initial),
        ),
      );
    }

    Future<void> drop(WidgetTester tester, int pot, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.byType(TopfGlas).at(pot));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('Fertig only once all Taler are spent', (tester) async {
      Map<String, int>? result;
      await pump(tester, (t) => result = t);

      expect(find.text('Noch 20 Taler'), findsOneWidget);
      await drop(tester, 0, 12);
      await drop(tester, 7, 7);
      expect(find.text('Noch 1 Taler'), findsOneWidget);
      expect(button(tester, 'Fertig').onPressed, isNull);

      await drop(tester, 2, 1);
      expect(find.text('Alles verteilt'), findsOneWidget);
      // A full Stadtkasse takes no more.
      await drop(tester, 3, 1);

      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();
      expect(find.text('Dein Stadthaushalt'), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.text('Weiter'));
      expect(result, {'kinder_bildung': 12, 'oepnv_rad': 1, 'gruen_klima': 7});
    });

    testWidgets('"−" puts a Taler back', (tester) async {
      await pump(tester, (_) {});

      await drop(tester, 1, 3);
      await tester.tap(
        find.bySemanticsLabel(
          'Einen Taler aus Soziales, Pflege & Gesundheit zurücklegen',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Noch 18 Taler'), findsOneWidget);
    });

    testWidgets('Neu verteilen starts from the earlier distribution', (
      tester,
    ) async {
      Map<String, int>? result;
      const earlier = {'kultur': 15, 'strassen': 5};
      await pump(tester, (t) => result = t, initial: earlier);

      expect(find.text('Alles verteilt'), findsOneWidget);
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weiter'));

      expect(result, earlier);
    });

    test('the pots are the backend areas', () {
      expect(haushaltToepfe.map((t) => t.id), [
        'kinder_bildung',
        'soziales',
        'oepnv_rad',
        'strassen',
        'kultur',
        'sport_freizeit',
        'sicherheit',
        'gruen_klima',
      ]);
    });
  });

  group('the start of onboarding', () {
    Future<_Profiles> start(WidgetTester tester, [UserProfile? profile]) async {
      phone(tester);
      final profiles = _Profiles();
      await tester.pumpWidget(
        MeinImpactApp.withProfile(
          opportunityRepository: _Repository(),
          profileStore: profiles,
          actionLogStore: _ActionLogs(),
          initialProfile: profile,
        ),
      );
      await tester.pumpAndSettle();
      return profiles;
    }

    Future<void> agree(WidgetTester tester) async {
      expect(button(tester, 'Einverstanden').onPressed, isNull);
      await tester.tap(find.text('Ich bin mindestens 16 Jahre alt.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Einverstanden'));
      await tester.pumpAndSettle();
    }

    testWidgets('intro, then the consent, then the questions', (tester) async {
      await start(tester);

      await tester.tap(find.text('Test starten · ca. 5 Min.'));
      await tester.pumpAndSettle();
      expect(find.text('Kurz zu deinen Daten'), findsOneWidget);

      // Back from the consent is the intro again.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Test starten · ca. 5 Min.'), findsOneWidget);

      await tester.tap(find.text('Test starten · ca. 5 Min.'));
      await tester.pumpAndSettle();
      await agree(tester);
      expect(find.text('Was passt eher zu dir?'), findsOneWidget);
    });

    testWidgets('"Lieber später" passes the consent and makes nothing up', (
      tester,
    ) async {
      final profiles = await start(tester);

      await tester.tap(find.textContaining('Erst mal nur Aktionen ansehen'));
      await tester.pumpAndSettle();
      await agree(tester);

      final saved = profiles.saved!;
      expect(saved.einwilligung, isNotNull);
      expect(saved.browsing, isTrue);
      expect(saved.plz, isNull);
      expect(saved.lebenslagen, isEmpty);
      expect(saved.prioritaeten, isEmpty);
      // No Stadthaushalt to catch up on: straight to the hand.
      expect(find.text('Wohin mit dem Geld deiner Stadt?'), findsNothing);
    });

    testWidgets('the profile starts the whole questionnaire later', (
      tester,
    ) async {
      final agreed = DateTime(2026, 11, 24);
      await start(tester, UserProfile.browsing(einwilligung: agreed));

      await tester.tap(find.text('Mein Profil'));
      await tester.pumpAndSettle();
      expect(find.text('Dein Wertebild'), findsNothing);
      await tester.tap(find.text('Fragebogen ausfüllen · ca. 5 Minuten'));
      await tester.pumpAndSettle();
      expect(find.text('Was passt eher zu dir?'), findsOneWidget);

      // Back from the first question is the profile again.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Fragebogen ausfüllen · ca. 5 Minuten'), findsOneWidget);
    });

    testWidgets('a profile from before catches up on consent and Taler', (
      tester,
    ) async {
      final profiles = await start(
        tester,
        const UserProfile(plz: '01067', lebenslagen: {'mieter'}),
      );

      await agree(tester);
      expect(profiles.saved?.einwilligung, isNotNull);
      expect(find.text('Wohin mit dem Geld deiner Stadt?'), findsOneWidget);
      // Required: there is no way to skip it.
      expect(find.text('Überspringen'), findsNothing);
    });
  });

  test('the consent date is kept with the profile', () {
    final profile = UserProfile.fromJson(
      UserProfile(einwilligung: DateTime(2026, 11, 24, 9, 30)).toJson(),
    );
    expect(profile.einwilligung, DateTime(2026, 11, 24, 9, 30));
    expect(UserProfile.fromJson(const {}).einwilligung, isNull);
  });

  test('only looking is kept with the profile', () {
    final profile = UserProfile.fromJson(
      UserProfile.browsing(einwilligung: DateTime(2026, 11, 24)).toJson(),
    );
    expect(profile.browsing, isTrue);
    expect(UserProfile.fromJson(const {}).browsing, isFalse);
  });

  test('the old Beispielprofil becomes only looking', () {
    final profile = UserProfile.fromJson(const {
      'werte': <String, Object?>{},
      'plz': '01067',
      'lebenslagen': ['mieter', 'oepnv', 'angestellt'],
      'prioritaeten': {'kultur': 20},
      'einwilligung': '2026-11-24T09:30:00.000',
    });
    expect(profile.browsing, isTrue);
    expect(profile.plz, isNull);
    expect(profile.lebenslagen, isEmpty);
    expect(profile.prioritaeten, isEmpty);
    expect(profile.einwilligung, DateTime(2026, 11, 24, 9, 30));
  });
}

class _Repository implements OpportunityRepository {
  @override
  Future<PlzLookup?> locate(String plz) async => null;

  @override
  Future<List<Opportunity>> pool({String? kreis}) async => const [];

  @override
  Future<ImpactNewsFeed> impactNews() async => const ImpactNewsFeed();

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) =>
      const Stream.empty();

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      const LetterRecipients();

  @override
  Future<void> markTracked(String opportunityId) async {}
}

class _Profiles extends UserProfileStore {
  UserProfile? saved;

  @override
  Future<void> save(UserProfile profile) async => saved = profile;
}

class _ActionLogs extends ActionLogStore {
  @override
  Future<ActionLog> load() async => const ActionLog();

  @override
  Future<void> save(ActionLog log) async {}
}
