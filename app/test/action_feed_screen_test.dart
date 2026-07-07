import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/meinimpact_app.dart';
import 'package:meinimpact/src/core/network/sse_event_parser.dart';
import 'package:meinimpact/src/features/feed/domain/action_repository.dart';
import 'package:meinimpact/src/features/feed/domain/civic_action.dart';
import 'package:meinimpact/src/features/feed/domain/mdb.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

void main() {
  testWidgets('renders recommended actions', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _FakeActionRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('MeinImpact'), findsWidgets);
    expect(find.text('Write to your representative'), findsWidgets);
    expect(find.text('Bewertung 90'), findsOneWidget);
  });

  testWidgets('switches between German and English', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _FakeActionRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('languageSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('Score 90'), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget);
  });

  testWidgets('renders empty recommendation state', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _EmptyActionRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Aktionen verfügbar.'), findsOneWidget);
  });

  testWidgets('renders empty recommendation state in English', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _EmptyActionRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('languageSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('No actions available yet.'), findsOneWidget);
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
}

class _FakeActionRepository implements ActionRepository {
  @override
  Future<List<ActionRecommendation>> recommendations(
    UserProfile profile,
  ) async {
    return const [
      ActionRecommendation(
        action: CivicAction(
          id: 'test-action',
          title: 'Write to your representative',
          actionType: 'representative_letter',
          summary: 'Ask a clear and respectful question.',
          region: 'Germany',
          effortMinutes: 3,
          impactHint: 'The response can be tracked later.',
          sourceUrl: 'https://example.org',
        ),
        score: 90,
        reasons: ['Matches democracy.'],
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
}
