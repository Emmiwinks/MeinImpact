import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A random id per install, created on first start. The backend uses it only
/// as the subject of the anonymous session token; it carries nothing about
/// the person and is never linked to what they do in the app.
class InstallationIdStore {
  const InstallationIdStore({FlutterSecureStorage? storage, Random? random})
      : _storage = storage ?? const FlutterSecureStorage(),
        _random = random;

  static const _key = 'installation_id';

  final FlutterSecureStorage _storage;
  final Random? _random;

  Future<String> load() async {
    String? existing;
    try {
      existing = await _storage.read(key: _key);
    } catch (_) {
      // Unreadable (e.g. a web key mismatch): a fresh id is harmless.
    }
    if (existing != null) return existing;
    final id = uuidV4(_random ?? Random.secure());
    await _storage.write(key: _key, value: id);
    return id;
  }
}

/// RFC 4122 version 4 UUID.
String uuidV4(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
