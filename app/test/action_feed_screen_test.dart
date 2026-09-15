import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/meinimpact_app.dart';
import 'package:meinimpact/src/core/network/sse_event_parser.dart';
import 'package:meinimpact/src/features/feed/domain/action_repository.dart';
import 'package:meinimpact/src/features/feed/domain/civic_action.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

void main() {
  testWidgets('renders topics grouped from the pool, no fabricated stats', (
    tester,
  ) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _GroupedTopicRepository()),
    );
    await tester.pumpAndSettle();

    // Petition and letter share topic_id 'klimaschutz' — one topic tile,
    // not two, and the headline is the higher-scored option's title.
    expect(find.text('Brief an deinen Abgeordneten'), findsOneWidget);
    expect(find.text('Petition zum Klimaschutz'), findsNothing);

    // Real, sourced fact — the topic's existential state badge/reason.
    expect(find.text('Entscheidung steht an'), findsOneWidget);
    expect(find.text('Kurz vor dem Quorum: 45.000 von 50.000'), findsOneWidget);

    // No invented score or time-estimate text anywhere.
    expect(find.textContaining('Bewertung'), findsNothing);
    expect(find.textContaining('Min.'), findsNothing);

    // No language switcher.
    expect(find.byKey(const Key('languageSelector')), findsNothing);
  });

  testWidgets('opening a topic shows both its options', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _GroupedTopicRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Brief an deinen Abgeordneten'));
    await tester.pumpAndSettle();

    expect(find.text('Petition unterschreiben'), findsOneWidget);
    expect(find.text('Brief schreiben'), findsOneWidget);
  });

  testWidgets('renders empty topics state', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _EmptyActionRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Themen verfügbar.'), findsOneWidget);
  });

  testWidgets('renders recommendation errors', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _FailingActionRepository()),
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
      MeinImpactApp(actionRepository: _EmptyActionRepository()),
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

CivicAction _petitionAction() => const CivicAction(
      id: 'petition-1',
      title: 'Petition zum Klimaschutz',
      actionType: 'petition_signature',
      summary: 'Eine Petition fordert mehr Klimaschutz.',
      region: 'Germany',
      sourceUrl: 'https://weact.campact.de/petitions/1',
      topicId: 'klimaschutz',
      engagementState: 'A',
      stateReason: 'Kurz vor dem Quorum: 45.000 von 50.000',
    );

CivicAction _letterAction() => const CivicAction(
      id: 'letter-1',
      title: 'Brief an deinen Abgeordneten',
      actionType: 'representative_letter',
      summary: 'Schreib deiner Abgeordneten zum Klimaschutzgesetz.',
      region: 'Germany',
      sourceUrl: 'https://dip.bundestag.de/vorgang/1',
      topicId: 'klimaschutz',
      engagementState: 'C',
      stateReason: null,
    );

class _GroupedTopicRepository implements ActionRepository {
  @override
  Future<List<ActionRecommendation>> recommendations(
    UserProfile profile,
  ) async {
    return [
      ActionRecommendation(
        action: _petitionAction(),
        score: 60,
        reasons: const ['Aktuell verfügbare Maßnahme.'],
      ),
      ActionRecommendation(
        action: _letterAction(),
        score: 90,
        reasons: const ['Passt zu deinen Werten.'],
      ),
    ];
  }

  @override
  Stream<SseEvent> streamDraft({
    required String actionId,
    required UserProfile profile,
    String letterType = 'brief',
  }) async* {
    yield const SseEvent(event: 'message', data: 'Draft');
    yield const SseEvent(event: 'message', data: '[DONE]');
  }

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Future<String> getContext({
    required String actionId,
    required UserProfile profile,
  }) async =>
      'Context.';
}

class _EmptyActionRepository implements ActionRepository {
  @override
  Future<List<ActionRecommendation>> recommendations(
    UserProfile profile,
  ) async {
    return const [];
  }

  @override
  Stream<SseEvent> streamDraft({
    required String actionId,
    required UserProfile profile,
    String letterType = 'brief',
  }) async* {}

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Future<String> getContext({
    required String actionId,
    required UserProfile profile,
  }) async =>
      'Context.';
}

class _FailingActionRepository implements ActionRepository {
  @override
  Future<List<ActionRecommendation>> recommendations(
    UserProfile profile,
  ) async {
    throw StateError('Backend unavailable');
  }

  @override
  Stream<SseEvent> streamDraft({
    required String actionId,
    required UserProfile profile,
    String letterType = 'brief',
  }) async* {}

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];

  @override
  Future<String> getContext({
    required String actionId,
    required UserProfile profile,
  }) async =>
      'Context.';
}
