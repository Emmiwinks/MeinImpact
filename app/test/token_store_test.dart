import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/core/security/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores tokens through secure storage wrapper', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const store = SecureTokenStore();

    await store.saveTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );

    expect(await store.readAccessToken(), 'access-token');
    expect(await store.readRefreshToken(), 'refresh-token');

    await store.clear();

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('clears in-memory tokens', () async {
    final store = InMemoryTokenStore();
    await store.saveTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );

    await store.clear();

    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });
}
