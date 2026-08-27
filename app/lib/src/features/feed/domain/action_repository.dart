import '../../../core/network/sse_event_parser.dart';
import 'civic_action.dart';
import 'mdb.dart';
import 'user_profile.dart';

abstract interface class ActionRepository {
  Future<List<ActionRecommendation>> recommendations(UserProfile profile);

  Stream<SseEvent> streamDraft({
    required String actionId,
    required UserProfile profile,
    String letterType,
  });

  Future<List<MdbOption>> lookupMdb(String plz);

  /// Returns an AI-generated paragraph explaining what this action means
  /// for someone matching [profile]'s demographics.
  Future<String> getContext({
    required String actionId,
    required UserProfile profile,
  });
}
