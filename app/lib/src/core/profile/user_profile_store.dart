import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/feed/domain/user_profile.dart';

class UserProfileStore {
  const UserProfileStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'user_profile_v1';
  // Where a profile that no longer parses is kept, so a format bug never
  // destroys it and it can still be recovered.
  static const _unreadableKey = 'user_profile_v1_unreadable';

  final FlutterSecureStorage _storage;

  /// The saved profile, or null when there is none. A profile that cannot be
  /// read is moved aside and null is returned, so startup never fails on it
  /// (it runs before `runApp`; a throw there leaves a blank screen).
  Future<UserProfile?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (error) {
      debugPrint('Saved profile unreadable, moved to $_unreadableKey: $error');
      await _storage.write(key: _unreadableKey, value: raw);
      await _storage.delete(key: _key);
      return null;
    }
  }

  Future<void> save(UserProfile profile) async {
    await _storage.write(key: _key, value: jsonEncode(profile.toJson()));
  }
}
