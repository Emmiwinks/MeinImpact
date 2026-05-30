import '../../feed/domain/action_repository.dart';
import '../../feed/domain/civic_action.dart';
import '../../feed/domain/user_profile.dart';
import '../../../core/network/sse_event_parser.dart';

class DemoActionRepository implements ActionRepository {
  @override
  Future<List<ActionRecommendation>> recommendations(
    UserProfile profile,
  ) async {
    return const [
      ActionRecommendation(
        action: CivicAction(
          id: 'solar-letter-bundestag',
          title: 'Ask your representative about community solar access',
          actionType: 'representative_letter',
          summary:
              'A committee vote will discuss community solar rules next week.',
          topics: ['climate', 'housing', 'energy'],
          region: 'Germany',
          effortMinutes: 3,
          impactHint:
              'The vote position can be checked after the committee week.',
          sourceUrl: 'https://www.bundestag.de/',
        ),
        score: 95,
        reasons: [
          'Matches selected topics: climate, housing.',
          'Can be completed in about three minutes.',
        ],
      ),
      ActionRecommendation(
        action: CivicAction(
          id: 'school-funding-petition',
          title: 'Support transparent school renovation funding',
          actionType: 'petition_signature',
          summary: 'A petition asks for clearer renovation funding timelines.',
          topics: ['education', 'democracy'],
          region: 'Germany',
          effortMinutes: 2,
          impactHint: 'The quorum status can be checked after the deadline.',
          sourceUrl: 'https://epetitionen.bundestag.de/',
        ),
        score: 76,
        reasons: [
          'Matches a public spending topic.',
          'Can be completed in about two minutes.',
        ],
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
    yield const SseEvent(
      event: 'draft.delta',
      data: 'Dear representative, I care about transparent decisions.',
    );
  }
}
