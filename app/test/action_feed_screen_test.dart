import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/meinimpact_app.dart';
import 'package:meinimpact/src/core/network/sse_event_parser.dart';
import 'package:meinimpact/src/features/feed/domain/action_repository.dart';
import 'package:meinimpact/src/features/feed/domain/civic_action.dart';
import 'package:meinimpact/src/features/feed/domain/user_profile.dart';

void main() {
  testWidgets('renders recommended actions', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _FakeActionRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('MeinImpact'), findsOneWidget);
    expect(find.text('Write to your representative'), findsOneWidget);
    expect(find.text('Score 90'), findsOneWidget);
  });

  testWidgets('renders empty recommendation state', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _EmptyActionRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('No actions available yet.'), findsOneWidget);
  });

  testWidgets('renders recommendation errors', (tester) async {
    await tester.pumpWidget(
      MeinImpactApp(actionRepository: _FailingActionRepository()),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not load recommendations:'),
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
          topics: ['democracy'],
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
    String? personalContext,
    String tone = 'respectful',
  }) async* {
    yield const SseEvent(event: 'draft.delta', data: 'Draft');
  }
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
    String? personalContext,
    String tone = 'respectful',
  }) async* {}
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
    String? personalContext,
    String tone = 'respectful',
  }) async* {}
}
