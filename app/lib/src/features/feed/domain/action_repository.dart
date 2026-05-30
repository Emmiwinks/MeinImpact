import '../../../core/network/sse_event_parser.dart';
import 'civic_action.dart';
import 'user_profile.dart';

abstract interface class ActionRepository {
  Future<List<ActionRecommendation>> recommendations(UserProfile profile);

  Stream<SseEvent> streamDraft({
    required String actionId,
    required UserProfile profile,
    String? personalContext,
    String tone,
  });
}
