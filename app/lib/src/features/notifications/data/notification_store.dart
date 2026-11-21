import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/notification_state.dart';

/// Keeps what notifications remember on the device, encrypted like the
/// action log: it names actions the user did and cards they looked at.
class NotificationStore {
  const NotificationStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'notifications_v1';

  final FlutterSecureStorage _storage;

  /// The saved state, or a fresh one when there is none or it cannot be
  /// read (then at worst a notification repeats).
  Future<NotificationState> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return const NotificationState();
      return NotificationState.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } catch (error) {
      debugPrint('Notification state could not be read: $error');
      return const NotificationState();
    }
  }

  Future<void> save(NotificationState state) async {
    await _storage.write(key: _key, value: jsonEncode(state.toJson()));
  }
}
