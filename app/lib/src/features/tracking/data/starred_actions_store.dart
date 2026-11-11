import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The done actions the user starred in Wirkung, by opportunity id: the
/// ones they want to hear about when something new turns up (push comes
/// later). Kept on the device and encrypted like the action log.
class StarredActionsStore {
  const StarredActionsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'starred_actions_v1';

  final FlutterSecureStorage _storage;

  /// The starred ids; empty when nothing is saved or it cannot be read.
  Future<Set<String>> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return {};
      return (jsonDecode(raw) as List<Object?>).cast<String>().toSet();
    } catch (error) {
      debugPrint('Starred actions could not be read: $error');
      return {};
    }
  }

  Future<void> save(Set<String> ids) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(ids.toList()));
    } catch (error) {
      // The star still shows for this session.
      debugPrint('Starred actions could not be saved: $error');
    }
  }
}
