import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/action_log.dart';

/// Keeps the action log on the device, encrypted like the profile: which
/// petitions someone signed reveals political opinions. Kept apart from the
/// profile so editing or redoing the profile never wipes it.
class ActionLogStore {
  const ActionLogStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'action_log_v1';
  // Where a log that no longer parses is kept, so a format bug never
  // destroys it and it can still be recovered.
  static const _unreadableKey = 'action_log_v1_unreadable';

  final FlutterSecureStorage _storage;

  /// The saved log, or an empty one. A log that cannot be read is moved
  /// aside, so startup never fails on it.
  Future<ActionLog> load() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _key);
    } catch (error) {
      debugPrint('Saved action log could not be read: $error');
      return const ActionLog();
    }
    if (raw == null) return const ActionLog();
    try {
      return ActionLog.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (error) {
      debugPrint('Action log unreadable, moved to $_unreadableKey: $error');
      await _storage.write(key: _unreadableKey, value: raw);
      await _storage.delete(key: _key);
      return const ActionLog();
    }
  }

  Future<void> save(ActionLog log) async {
    await _storage.write(key: _key, value: jsonEncode(log.toJson()));
  }
}
