import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/app/theme/appearance_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('follows the phone until something is chosen', () async {
    FlutterSecureStorage.setMockInitialValues({});

    expect(await const AppearanceStore().load(), ThemeMode.system);
  });

  test('saves and loads the choice', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const store = AppearanceStore();

    await store.save(ThemeMode.dark);

    expect(await store.load(), ThemeMode.dark);
  });

  test('an unknown value falls back to the phone', () async {
    FlutterSecureStorage.setMockInitialValues({'appearance_v1': 'sepia'});

    expect(await const AppearanceStore().load(), ThemeMode.system);
  });
}
