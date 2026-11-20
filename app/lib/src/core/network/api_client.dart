import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../security/token_store.dart';
import 'sse_event_parser.dart';

class ApiClient {
  ApiClient({
    required Uri baseUrl,
    required TokenStore tokenStore,
    http.Client? httpClient,
    int maxAttempts = 3,
    Duration retryDelay = const Duration(milliseconds: 200),
    Duration requestTimeout = const Duration(seconds: 15),
    Future<void> Function(Duration duration)? sleep,
  })  : _baseUrl = baseUrl,
        _tokenStore = tokenStore,
        _httpClient = httpClient ?? http.Client(),
        _maxAttempts = maxAttempts,
        _retryDelay = retryDelay,
        _requestTimeout = requestTimeout,
        _sleep = sleep ?? ((duration) => Future<void>.delayed(duration)) {
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'Must be at least 1.',
      );
    }
  }

  final Uri _baseUrl;
  final TokenStore _tokenStore;
  final http.Client _httpClient;
  final int _maxAttempts;
  final Duration _retryDelay;
  final Duration _requestTimeout;
  final Future<void> Function(Duration duration) _sleep;

  // Remembered from [createAnonymousSession], so a session that failed at
  // startup or expired (access tokens last 15 minutes) can be renewed on
  // the next request instead of only on the next app start.
  String? _installationId;
  String? _appVersion;
  Future<void>? _sessionInFlight;

  Future<void> createAnonymousSession({
    required String installationId,
    required String appVersion,
  }) {
    _installationId = installationId;
    _appVersion = appVersion;
    return _renewSession();
  }

  // One request at a time: concurrent callers share it.
  Future<void> _renewSession() {
    return _sessionInFlight ??= _requestSession().whenComplete(
      () => _sessionInFlight = null,
    );
  }

  Future<void> _requestSession() async {
    final installationId = _installationId;
    final appVersion = _appVersion;
    if (installationId == null || appVersion == null) {
      throw const ApiException('Missing access token.');
    }
    final response = await _postWithRetry(
      '/v1/auth/anonymous-session',
      headers: const {'Content-Type': 'application/json'},
      body: {
        'installation_id': installationId,
        'app_version': appVersion,
      },
    );
    final body = _decodeJson(response);
    await _tokenStore.saveTokens(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
    );
  }

  Future<Map<String, Object?>> getJson(String path) async {
    final response = await _sendAuthorized(
      (headers) => _sendWithRetry(
        () => _httpClient.get(_resolve(path), headers: headers),
        statusCode: (r) => r.statusCode,
      ),
      statusCode: (r) => r.statusCode,
    );
    return _decodeJson(response);
  }

  Future<Map<String, Object?>> postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _sendAuthorized(
      (headers) => _postWithRetry(path, headers: headers, body: body),
      statusCode: (r) => r.statusCode,
    );
    return _decodeJson(response);
  }

  Stream<SseEvent> postSse(
    String path,
    Map<String, Object?> body,
  ) async* {
    final response = await _sendAuthorized(
      (headers) {
        final request = http.Request('POST', _resolve(path));
        request.headers.addAll(headers);
        request.headers['Accept'] = 'text/event-stream';
        request.body = jsonEncode(body);
        return _sendStreamingRequest(request);
      },
      statusCode: (r) => r.statusCode,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Streaming request failed: ${response.statusCode}.');
    }

    final chunks = response.stream.transform(utf8.decoder).handleError(
      (Object error) {
        if (error is TimeoutException) {
          throw const ApiException('Network request timed out.');
        }
        throw const ApiException('Network request failed.');
      },
      test: (error) =>
          error is TimeoutException || error is http.ClientException,
    );

    final parser = SseEventParser();
    await for (final chunk in chunks) {
      for (final event in parser.addChunk(chunk)) {
        yield event;
      }
    }
    for (final event in parser.close()) {
      yield event;
    }
  }

  // Sends with the stored token. Without one, or when the backend rejects
  // it, gets a new session first and sends once more.
  Future<T> _sendAuthorized<T>(
    Future<T> Function(Map<String, String> headers) send, {
    required int Function(T response) statusCode,
  }) async {
    final inFlight = _sessionInFlight;
    if (inFlight != null) {
      await inFlight.catchError((Object _) {});
    }
    var renewed = false;
    var accessToken = await _tokenStore.readAccessToken();
    if (accessToken == null) {
      await _renewSession();
      renewed = true;
      accessToken = await _tokenStore.readAccessToken();
    }
    final response = await send(_authorizedJsonHeaders(accessToken));
    if (statusCode(response) != 401 || renewed || _installationId == null) {
      return response;
    }
    await _renewSession();
    return send(_authorizedJsonHeaders(await _tokenStore.readAccessToken()));
  }

  Map<String, String> _authorizedJsonHeaders(String? accessToken) {
    if (accessToken == null) {
      throw const ApiException('Missing access token.');
    }
    return {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };
  }

  Future<http.Response> _postWithRetry(
    String path, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    return _sendWithRetry(
      () => _httpClient.post(
        _resolve(path),
        headers: headers,
        body: jsonEncode(body),
      ),
      statusCode: (response) => response.statusCode,
    );
  }

  Future<T> _sendWithRetry<T>(
    Future<T> Function() send, {
    required int Function(T response) statusCode,
  }) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final response = await send().timeout(_requestTimeout);
        if (!_isRetryableStatus(statusCode(response)) ||
            attempt == _maxAttempts) {
          return response;
        }
      } on TimeoutException {
        if (attempt == _maxAttempts) {
          throw const ApiException('Network request timed out.');
        }
      } on http.ClientException {
        if (attempt == _maxAttempts) {
          throw const ApiException('Network request failed.');
        }
      }
      await _sleep(_delayForAttempt(attempt));
    }
    throw const ApiException('Network request failed.');
  }

  Future<http.StreamedResponse> _sendStreamingRequest(
    http.Request request,
  ) async {
    try {
      // Bounds the wait for the response to start, not the stream itself.
      return await _httpClient.send(request).timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiException('Network request timed out.');
    } on http.ClientException {
      throw const ApiException('Network request failed.');
    }
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 429 || (statusCode >= 500 && statusCode < 600);
  }

  Duration _delayForAttempt(int attempt) {
    return Duration(milliseconds: _retryDelay.inMilliseconds * attempt);
  }

  Map<String, Object?> _decodeJson(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Request failed: ${response.statusCode}.',
        statusCode: response.statusCode,
      );
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
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException: $message';
}
