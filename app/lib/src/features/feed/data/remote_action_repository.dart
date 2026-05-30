import '../../../core/network/api_client.dart';
import '../../../core/network/sse_event_parser.dart';
import '../domain/action_repository.dart';
import '../domain/civic_action.dart';
import '../domain/user_profile.dart';

class RemoteActionRepository implements ActionRepository {
  const RemoteActionRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<ActionRecommendation>> recommendations(
    UserProfile profile,
  ) async {
    final response = await _apiClient.postJson('/v1/actions/recommendations', {
      'profile': profile.toJson(),
      'limit': 5,
    });
    final rawItems = response['recommendations'];
    if (rawItems is! List<Object?>) {
      throw const ApiException('Expected recommendations list.');
    }
    return rawItems
        .whereType<Map<String, Object?>>()
        .map(ActionRecommendation.fromJson)
        .toList(growable: false);
  }

  @override
  Stream<SseEvent> streamDraft({
    required String actionId,
    required UserProfile profile,
    String? personalContext,
    String tone = 'respectful',
  }) {
    return _apiClient.postSse('/v1/actions/$actionId/drafts/stream', {
      'profile': profile.toJson(),
      'personal_context': personalContext,
      'tone': tone,
    });
  }
}
