import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The cards the user threw away from the hand, by opportunity id: they
/// are not dealt again. Kept on the device and encrypted like the action
/// log.
class DismissedCardsStore {
  const DismissedCardsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'dismissed_cards_v1';

  final FlutterSecureStorage _storage;

  /// The thrown-away ids; empty when nothing is saved or it cannot be read.
  Future<Set<String>> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return {};
      return (jsonDecode(raw) as List<Object?>).cast<String>().toSet();
    } catch (error) {
      debugPrint('Thrown-away cards could not be read: $error');
      return {};
    }
  }

  Future<void> save(Set<String> ids) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(ids.toList()));
    } catch (error) {
      // The card stays away for this session.
      debugPrint('Thrown-away cards could not be saved: $error');
    }
  }
}
