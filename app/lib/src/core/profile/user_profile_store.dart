import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/feed/domain/user_profile.dart';

class UserProfileStore {
  const UserProfileStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'user_profile_v1';

  final FlutterSecureStorage _storage;

  Future<UserProfile?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    return UserProfile.fromJson(
      jsonDecode(raw) as Map<String, Object?>,
    );
  }

  Future<void> save(UserProfile profile) async {
    await _storage.write(key: _key, value: jsonEncode(profile.toJson()));
  }
}
