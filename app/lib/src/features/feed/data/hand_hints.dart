import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One-time hints on the hand, remembered on the device so each shows only
/// once. Off (every hint counts as seen, so tests and demos show none)
/// until `main` sets [current].
class HandHints {
  HandHints._(this._storage, {required bool turnSeen}) : _turnSeen = turnSeen;

  HandHints.off()
      : _storage = null,
        _turnSeen = true;

  /// Nothing seen yet, kept in memory only.
  @visibleForTesting
  HandHints.unseen()
      : _storage = null,
        _turnSeen = false;

  static HandHints current = HandHints.off();

  static const _key = 'hand_hints_v1';

  final FlutterSecureStorage? _storage;
  bool _turnSeen;

  /// The front card turned over and back once by itself, or the user
  /// turned a card: either way they know a card has a back.
  bool get turnSeen => _turnSeen;

  static Future<HandHints> load({FlutterSecureStorage? storage}) async {
    final store = storage ?? const FlutterSecureStorage();
    try {
      final raw = await store.read(key: _key);
      final seen = raw == null
          ? const <String, Object?>{}
          : jsonDecode(raw) as Map<String, Object?>;
      return HandHints._(store, turnSeen: seen['turn'] == true);
    } catch (error) {
      debugPrint('Hand hints could not be read: $error');
      // Better no hint than one on every start.
      return HandHints._(store, turnSeen: true);
    }
  }

  Future<void> markTurnSeen() async {
    if (_turnSeen) return;
    _turnSeen = true;
    final storage = _storage;
    if (storage == null) return;
    try {
      await storage.write(key: _key, value: jsonEncode({'turn': true}));
    } catch (error) {
      debugPrint('Hand hints could not be saved: $error');
    }
  }
}
