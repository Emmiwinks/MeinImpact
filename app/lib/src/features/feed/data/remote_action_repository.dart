import '../../../core/network/api_client.dart';
import '../../../core/network/sse_event_parser.dart';
import '../domain/action_repository.dart';
import '../domain/civic_action.dart';
import '../domain/user_profile.dart';
import 'local_feed_scorer.dart';

class RemoteActionRepository implements ActionRepository {
  const RemoteActionRepository(this._apiClient);

  final ApiClient _apiClient;
  static const _scorer = LocalFeedScorer();

  @override
  Future<List<ActionRecommendation>> recommendations(
    UserProfile profile,
  ) async {
    final pool = await _fetchPool();
    return _scorer.score(pool, profile);
  }

  Future<List<CivicAction>> _fetchPool() async {
    final response = await _apiClient.getJson('/v1/actions/pool');
    final rawItems = response['actions'];
    if (rawItems is! List<Object?>) {
      throw const ApiException('Expected actions list.');
    }
    return rawItems
        .whereType<Map<String, Object?>>()
        .map(CivicAction.fromJson)
        .toList(growable: false);
  }

  @override
  Stream<SseEvent> streamDraft({
    required String actionId,
    required UserProfile profile,
    String letterType = 'brief',
  }) {
    return _apiClient.postSse('/v1/letters/stream', {
      'action_id': actionId,
      'type': letterType,
      'recipient_name': 'Ihre/n Abgeordnete/n',
      'recipient_party': 'unbekannt',
      'recipient_wahlkreis': null,
      'tone_descriptors': profile.deriveToneDescriptors(),
      'lebenssituation': profile.blacklist.isEmpty ? <String>[] : <String>[],
      'sektor': null,
      'plz_prefix': null,
      'wohnsituation': null,
    });
  }
}
