import '../../../core/network/api_client.dart';
import '../../../core/network/sse_event_parser.dart';
import '../domain/action_repository.dart';
import '../domain/civic_action.dart';
import '../domain/mdb.dart';
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
      'recipient_name': profile.mdbName ?? 'Ihre Abgeordnete',
      'recipient_party': profile.mdbParty ?? '',
      'recipient_wahlkreis': profile.mdbWahlkreis,
      'tone_descriptors': profile.deriveToneDescriptors(),
      'lebenssituation': profile.lebenssituation,
      'sektor': profile.sektor,
      'plz_prefix': profile.plz != null && profile.plz!.length >= 2
          ? profile.plz!.substring(0, 2)
          : null,
      'wohnsituation': profile.wohnsituation,
    });
  }

  @override
  Future<String> getContext({
    required String actionId,
    required UserProfile profile,
  }) async {
    final response = await _apiClient.postJson(
      '/v1/actions/$actionId/context',
      {
        'lebenssituation': profile.lebenssituation,
        'sektor': profile.sektor,
        'plz_prefix': profile.plz != null && profile.plz!.length >= 2
            ? profile.plz!.substring(0, 2)
            : null,
        'wohnsituation': profile.wohnsituation,
      },
    );
    return response['context'] as String? ?? '';
  }

  @override
  Future<List<MdbOption>> lookupMdb(String plz) async {
    try {
      final response = await _apiClient.getJson('/v1/mdb?plz=$plz');
      final rawItems = response['results'];
      if (rawItems is! List<Object?>) return const [];
      return rawItems
          .whereType<Map<String, Object?>>()
          .map(MdbOption.fromJson)
          .toList(growable: false);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }
}
