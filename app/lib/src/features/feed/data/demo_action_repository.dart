import '../../feed/domain/action_repository.dart';
import '../../feed/domain/civic_action.dart';
import '../../feed/domain/mdb.dart';
import '../../feed/domain/user_profile.dart';
import '../../../core/network/sse_event_parser.dart';
import 'demo_action_copy.dart';

class DemoActionRepository implements ActionRepository {
  const DemoActionRepository(this.copy);

  final DemoActionCopy copy;

  @override
  Future<List<ActionRecommendation>> recommendations(
    UserProfile profile,
  ) async {
    return [
      ActionRecommendation(
        action: CivicAction(
          id: 'solar-letter-bundestag',
          title: copy.solarTitle,
          actionType: 'representative_letter',
          summary: copy.solarSummary,
          region: 'Germany',
          effortMinutes: 3,
          impactHint: copy.solarImpactHint,
          sourceUrl: 'https://www.bundestag.de/',
        ),
        score: 95,
        reasons: [
          copy.solarReasonEffort,
        ],
      ),
      ActionRecommendation(
        action: CivicAction(
          id: 'school-funding-petition',
          title: copy.schoolTitle,
          actionType: 'petition_signature',
          summary: copy.schoolSummary,
          region: 'Germany',
          effortMinutes: 2,
          impactHint: copy.schoolImpactHint,
          sourceUrl: 'https://epetitionen.bundestag.de/',
        ),
        score: 76,
        reasons: [
          copy.schoolReasonSpending,
          copy.schoolReasonEffort,
        ],
      ),
    ];
  }

  @override
  Stream<SseEvent> streamDraft({
    required String actionId,
    required UserProfile profile,
    String letterType = 'brief',
  }) async* {
    yield SseEvent(event: 'message', data: copy.draftDelta);
    yield const SseEvent(event: 'message', data: '[DONE]');
  }

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async => const [];
}
