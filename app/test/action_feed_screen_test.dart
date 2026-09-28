import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/meinimpact_app.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';

void main() {
  testWidgets('renders opportunities from the pool, no fabricated stats', (
    tester,
  ) async {
    await tester.pumpWidget(
      MeinImpactApp(opportunityRepository: _PoolRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Petition zum Klimaschutz'), findsOneWidget);
    expect(find.text('openPetition'), findsOneWidget);

    // No invented score or time-estimate text anywhere.
    expect(find.textContaining('Bewertung'), findsNothing);
    expect(find.textContaining('Min.'), findsNothing);

    // No language switcher.
    expect(find.byKey(const Key('languageSelector')), findsNothing);
  });

  testWidgets('opening an opportunity shows its action button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MeinImpactApp(opportunityRepository: _PoolRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Petition zum Klimaschutz'));
    await tester.pumpAndSettle();

    expect(find.text('Petition unterschreiben'), findsOneWidget);
  });

  testWidgets('renders empty pool state', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(opportunityRepository: _EmptyRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Themen verfügbar.'), findsOneWidget);
  });

  testWidgets('renders pool-loading errors', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(opportunityRepository: _FailingRepository()),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Empfehlungen konnten nicht geladen werden:'),
      findsOneWidget,
    );
  });

  testWidgets('bottom navigation has three tabs and switches to Wirkung', (
    tester,
  ) async {
    await tester.pumpWidget(
      MeinImpactApp(opportunityRepository: _EmptyRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Mein Profil'), findsOneWidget);
    expect(find.text('Meine Themen'), findsOneWidget);
    expect(find.text('Meine Wirkung'), findsOneWidget);

    await tester.tap(find.text('Meine Wirkung'));
    await tester.pumpAndSettle();

    // Distinctive mockup body text — not shown as a real stat, per the
    // "no made-up facts" rule extending to the mockup tab too.
    expect(find.textContaining('noch nicht angebunden'), findsOneWidget);
    // SectionLabel renders its text upper-cased.
    expect(find.text('BEISPIELANSICHT'), findsOneWidget);
  });
}

Opportunity _petitionOpportunity() => Opportunity(
      id: 'petition-1',
      sourceOrg: 'openPetition',
      decisionObject: 'Klimaschutzgesetz verschärfen',
      plainLanguageTitle: 'Petition zum Klimaschutz',
      plainLanguageSummary: 'Eine Petition fordert mehr Klimaschutz.',
      affectedTags: const ['Umwelt/Natur'],
      region: 'bund',
      werteRelevanz: const {},
      sourceUrl: 'https://weact.campact.de/petitions/1',
      actionTypes: const ['petition'],
      proArgumente: const [],
      contraArgumente: const [],
      personalImpactSnippets: const {},
      retrievedAt: DateTime(2026, 9, 27),
    );

class _PoolRepository implements OpportunityRepository {
  @override
  Future<List<Opportunity>> pool() async => [_petitionOpportunity()];

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];
}

class _EmptyRepository implements OpportunityRepository {
  @override
  Future<List<Opportunity>> pool() async => const [];

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];
}

class _FailingRepository implements OpportunityRepository {
  @override
  Future<List<Opportunity>> pool() async {
    throw StateError('Backend unavailable');
  }

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];
}
