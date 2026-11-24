import '../../../core/network/api_client.dart';
import '../../tracking/domain/impact_news.dart';
import '../domain/home_location.dart';
import '../domain/letter_recipients.dart';
import '../domain/opportunity.dart';
import '../domain/opportunity_repository.dart';

class RemoteOpportunityRepository implements OpportunityRepository {
  const RemoteOpportunityRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<Opportunity>> pool({String? kreis}) async {
    final response = await _apiClient.getJson(
      kreis == null
          ? '/v1/opportunities/pool'
          : '/v1/opportunities/pool?kreis=$kreis',
    );
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
  Future<PlzLookup?> locate(String plz) async {
    // The PLZ goes in the body: the server's access log never shows it.
    try {
      final response = await _apiClient.postJson('/v1/location', {'plz': plz});
      return PlzLookup.fromJson(response);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<LetterRecipients> letterRecipients(String opportunityId) async {
    // The id goes in the body: the server's access log never shows which
    // decision someone drafts a letter on.
    final response = await _apiClient.postJson('/v1/opportunities/recipients', {
      'opportunity_id': opportunityId,
    });
    return LetterRecipients.fromJson(response);
  }

  @override
  Future<void> markTracked(String opportunityId) async {
    // The id goes in the body: the server's access log never shows it.
    await _apiClient.postJson('/v1/opportunities/tracked', {
      'opportunity_id': opportunityId,
    });
  }

  @override
  Future<ImpactNewsFeed> impactNews() async {
    final response = await _apiClient.getJson('/v1/opportunities/news');
    return ImpactNewsFeed.fromJson(response);
  }

  @override
  Stream<String> streamLetter(String opportunityId, {String? notes}) async* {
    final events = _apiClient.postSse('/v1/letters/stream', {
      'opportunity_id': opportunityId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    await for (final event in events) {
      if (event.data == '[DONE]') return;
      yield event.data;
    }
  }
}
