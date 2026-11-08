import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/core/security/installation_id_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates one id per install and keeps it', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const store = InstallationIdStore();

    final first = await store.load();

    expect(await store.load(), first);
    // The backend parses it as a UUID
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(first, matches(uuid));
  });

  test('different installs get different ids', () {
    expect(uuidV4(Random(1)), isNot(uuidV4(Random(2))));
  });
}
