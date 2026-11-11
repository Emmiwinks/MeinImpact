import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/meinimpact_app.dart';
import 'package:meinimpact/src/features/feed/domain/letter_recipients.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity.dart';
import 'package:meinimpact/src/features/feed/domain/opportunity_repository.dart';
import 'package:meinimpact/src/features/tracking/domain/impact_news.dart';

void main() {
  testWidgets('renders opportunities from the pool, no fabricated stats', (
    tester,
  ) async {
    await tester.pumpWidget(
      MeinImpactApp(opportunityRepository: _PoolRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('^Karte 1 von 1')), findsOneWidget);
    expect(find.text('Petition zum Klimaschutz'), findsOneWidget);
    // Kind of participation, straight from the registry.
    expect(find.text('Petition'), findsOneWidget);

    // No invented score or time-estimate text anywhere.
    expect(find.textContaining('Bewertung'), findsNothing);
    expect(find.textContaining('Min.'), findsNothing);

    // No language switcher.
    expect(find.byKey(const Key('languageSelector')), findsNothing);
  });

  testWidgets('turning a card over shows its source and action button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MeinImpactApp(opportunityRepository: _PoolRepository()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Petition unterschreiben'), findsOneWidget);

    await tester.tap(find.text('Petition zum Klimaschutz'));
    await tester.pumpAndSettle();

    expect(find.text('Petition · WeAct'), findsOneWidget);
    expect(
      find.text('Eine Petition fordert mehr Klimaschutz.'),
      findsOneWidget,
    );
    expect(find.text('Petition unterschreiben'), findsOneWidget);
  });

  testWidgets('renders empty pool state', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(opportunityRepository: _EmptyRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gerade gibt es keine offenen Aktionen.'), findsOneWidget);
  });

  testWidgets('renders pool-loading errors and retries', (tester) async {
    final repository = _FailingRepository();
    await tester.pumpWidget(MeinImpactApp(opportunityRepository: repository));
    await tester.pumpAndSettle();

    expect(
      find.text('Deine Karten konnten nicht geladen werden.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Nochmal versuchen'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
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
    expect(find.text('Meine Aktionen'), findsOneWidget);
    expect(find.text('Mein Impact'), findsOneWidget);

    await tester.tap(find.text('Mein Impact'));
    await tester.pumpAndSettle();

    // No action done yet: the tab explains how it fills.
    expect(find.textContaining('Noch keine Aktion erledigt'), findsOneWidget);
  });
}

Opportunity _petitionOpportunity() => Opportunity(
      id: 'petition-1',
      sourceOrg: 'WeAct',
      sourceUrl: 'https://weact.campact.de/petitions/1',
      kind: OpportunityKind.petition,
      isAnnounced: false,
      region: 'bund',
      title: 'Petition zum Klimaschutz',
      summary: 'Eine Petition fordert mehr Klimaschutz.',
      affectedTags: const ['Umwelt/Natur'],
      werteRelevanz: const {},
      proArgumente: const [],
      contraArgumente: const [],
      personalImpactSnippets: const {},
      firstSeenAt: DateTime(2026, 11, 1),
    );

class _PoolRepository implements OpportunityRepository {
  @override
  Future<List<Opportunity>> pool() async => [_petitionOpportunity()];

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) =>
      const Stream.empty();

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      const LetterRecipients();

  @override
  Future<void> markTracked(String opportunityId) async {}

  @override
  Future<ImpactNewsFeed> impactNews() async => const ImpactNewsFeed();
}

class _EmptyRepository implements OpportunityRepository {
  @override
  Future<List<Opportunity>> pool() async => const [];

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) =>
      const Stream.empty();

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      const LetterRecipients();

  @override
  Future<void> markTracked(String opportunityId) async {}

  @override
  Future<ImpactNewsFeed> impactNews() async => const ImpactNewsFeed();
}

class _FailingRepository implements OpportunityRepository {
  int calls = 0;

  @override
  Future<List<Opportunity>> pool() async {
    calls++;
    throw StateError('Backend unavailable');
  }

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) =>
      const Stream.empty();

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async =>
      const LetterRecipients();

  @override
  Future<void> markTracked(String opportunityId) async {}

  @override
  Future<ImpactNewsFeed> impactNews() async => const ImpactNewsFeed();
}
