import '../../../core/network/api_client.dart';
import '../domain/mdb.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_repository.dart';

class RemoteOpportunityRepository implements OpportunityRepository {
  const RemoteOpportunityRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<Opportunity>> pool() async {
    final response = await _apiClient.getJson('/v1/opportunities/pool');
    final rawItems = response['opportunities'];
    if (rawItems is! List<Object?>) {
      throw const ApiException('Expected opportunities list.');
    }
    return rawItems
        .whereType<Map<String, Object?>>()
        .map(Opportunity.fromJson)
        .toList(growable: false);
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
