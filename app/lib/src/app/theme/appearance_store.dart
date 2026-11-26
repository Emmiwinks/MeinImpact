import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Whether the card table is light, dark or follows the phone, as chosen in
/// "Mein Profil". Kept on the device.
class AppearanceStore {
  const AppearanceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'appearance_v1';

  final FlutterSecureStorage _storage;

  /// The saved choice; the phone's setting when nothing is saved or it
  /// cannot be read.
  Future<ThemeMode> load() async {
    try {
      final raw = await _storage.read(key: _key);
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == raw,
        orElse: () => ThemeMode.system,
      );
    } catch (error) {
      debugPrint('Appearance could not be read: $error');
      return ThemeMode.system;
    }
  }

  Future<void> save(ThemeMode mode) async {
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (error) {
      // The choice holds for this session.
      debugPrint('Appearance could not be saved: $error');
    }
  }
}
