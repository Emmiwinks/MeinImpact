import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app version file matches pubspec version', () {
    final version = File('VERSION').readAsStringSync().trim();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('version: $version'));
  });
}
