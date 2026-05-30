import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meinimpact/src/core/network/api_client.dart';
import 'package:meinimpact/src/core/security/token_store.dart';

void main() {
  test('rejects invalid retry limits', () {
    expect(
      () => ApiClient(
        baseUrl: Uri.parse('https://api.example.test/'),
        tokenStore: InMemoryTokenStore(),
        maxAttempts: 0,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('retries transient JSON failures before returning success', () async {
    var calls = 0;
    final tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(
      accessToken: 'secret-access-token',
      refreshToken: 'secret-refresh-token',
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        calls += 1;
        if (calls < 3) {
          return http.Response('temporary failure', 503);
        }
        return http.Response('{"ok":true}', 200);
      }),
      retryDelay: Duration.zero,
    );

    final body = await client.postJson('/v1/test', const {});

    expect(calls, 3);
    expect(body['ok'], isTrue);
  });

  test('does not retry non-transient JSON failures', () async {
    var calls = 0;
    final tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(
      accessToken: 'secret-access-token',
      refreshToken: 'secret-refresh-token',
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        calls += 1;
        return http.Response('bad request', 400);
      }),
      retryDelay: Duration.zero,
    );

    await expectLater(
      client.postJson('/v1/test', const {}),
      throwsA(isA<ApiException>()),
    );

    expect(calls, 1);
  });

  test('maps bounded network failures without leaking tokens', () async {
    var calls = 0;
    final tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(
      accessToken: 'secret-access-token',
      refreshToken: 'secret-refresh-token',
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        calls += 1;
        throw http.ClientException('network down');
      }),
      retryDelay: Duration.zero,
    );

    Object? thrown;
    try {
      await client.postJson('/v1/test', const {});
    } on Object catch (error) {
      thrown = error;
    }

    expect(calls, 3);
    expect(thrown, isA<ApiException>());
    expect(thrown.toString(), contains('Network request failed.'));
    expect(thrown.toString(), isNot(contains('secret-access-token')));
    expect(thrown.toString(), isNot(contains('secret-refresh-token')));
  });

  test('maps request timeouts to generic API errors', () async {
    final tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(
      accessToken: 'secret-access-token',
      refreshToken: 'secret-refresh-token',
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        throw TimeoutException('slow network');
      }),
      maxAttempts: 1,
      retryDelay: Duration.zero,
    );

    await expectLater(
      client.postJson('/v1/test', const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.toString(),
          'message',
          contains('Network request timed out.'),
        ),
      ),
    );
  });

  test('retries anonymous session creation on transient failures', () async {
    var calls = 0;
    final tokenStore = InMemoryTokenStore();
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        calls += 1;
        if (calls == 1) {
          return http.Response('too many requests', 429);
        }
        return http.Response(
          '{"access_token":"access","refresh_token":"refresh",'
          '"expires_in_seconds":900}',
          201,
        );
      }),
      retryDelay: Duration.zero,
    );

    await client.createAnonymousSession(
      installationId: 'installation-id',
      appVersion: '0.1.2',
    );

    expect(calls, 2);
    expect(await tokenStore.readAccessToken(), 'access');
    expect(await tokenStore.readRefreshToken(), 'refresh');
  });

  test('rejects non-object JSON responses', () async {
    final tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(
      accessToken: 'secret-access-token',
      refreshToken: 'secret-refresh-token',
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        return http.Response('["not", "an", "object"]', 200);
      }),
      retryDelay: Duration.zero,
    );

    await expectLater(
      client.postJson('/v1/test', const {}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.toString(),
          'message',
          contains('Expected a JSON object response.'),
        ),
      ),
    );
  });

  test('streams SSE responses', () async {
    final tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(
      accessToken: 'secret-access-token',
      refreshToken: 'secret-refresh-token',
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        return http.Response('event: draft.delta\ndata: hello\n\n', 200);
      }),
      retryDelay: Duration.zero,
    );

    final events = await client.postSse('/v1/stream', const {}).toList();

    expect(events, hasLength(1));
    expect(events.single.event, 'draft.delta');
    expect(events.single.data, 'hello');
  });

  test('rejects failed SSE responses', () async {
    final tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(
      accessToken: 'secret-access-token',
      refreshToken: 'secret-refresh-token',
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        return http.Response('server error', 503);
      }),
      retryDelay: Duration.zero,
    );

    await expectLater(
      client.postSse('/v1/stream', const {}).toList(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.toString(),
          'message',
          contains('Streaming request failed: 503.'),
        ),
      ),
    );
  });

  test('maps SSE network failures', () async {
    final tokenStore = InMemoryTokenStore();
    await tokenStore.saveTokens(
      accessToken: 'secret-access-token',
      refreshToken: 'secret-refresh-token',
    );
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test/'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        throw http.ClientException('network down');
      }),
      retryDelay: Duration.zero,
    );

    await expectLater(
      client.postSse('/v1/stream', const {}).toList(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.toString(),
          'message',
          contains('Network request failed.'),
        ),
      ),
    );
  });
}
