import 'dart:convert';

import 'package:http/http.dart' as http;

import '../security/token_store.dart';
import 'sse_event_parser.dart';

class ApiClient {
  ApiClient({
    required Uri baseUrl,
    required TokenStore tokenStore,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl,
        _tokenStore = tokenStore,
        _httpClient = httpClient ?? http.Client();

  final Uri _baseUrl;
  final TokenStore _tokenStore;
  final http.Client _httpClient;

  Future<void> createAnonymousSession({
    required String installationId,
    required String appVersion,
  }) async {
    final response = await _httpClient.post(
      _resolve('/v1/auth/anonymous-session'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'installation_id': installationId,
        'app_version': appVersion,
      }),
    );
    final body = _decodeJson(response);
    await _tokenStore.saveTokens(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
    );
  }

  Future<Map<String, Object?>> postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _httpClient.post(
      _resolve(path),
      headers: await _authorizedJsonHeaders(),
      body: jsonEncode(body),
    );
    return _decodeJson(response);
  }

  Stream<SseEvent> postSse(
    String path,
    Map<String, Object?> body,
  ) async* {
    final request = http.Request('POST', _resolve(path));
    request.headers.addAll(await _authorizedJsonHeaders());
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode(body);

    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Streaming request failed: ${response.statusCode}.');
    }

    final parser = SseEventParser();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      for (final event in parser.addChunk(chunk)) {
        yield event;
      }
    }
    for (final event in parser.close()) {
      yield event;
    }
  }

  Future<Map<String, String>> _authorizedJsonHeaders() async {
    final accessToken = await _tokenStore.readAccessToken();
    if (accessToken == null) {
      throw const ApiException('Missing access token.');
    }
    return {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };
  }

  Map<String, Object?> _decodeJson(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Request failed: ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    throw const ApiException('Expected a JSON object response.');
  }

  Uri _resolve(String path) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return _baseUrl.resolve(normalizedPath);
  }
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => 'ApiException: $message';
}
