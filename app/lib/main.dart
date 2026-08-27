import 'package:flutter/material.dart';

import 'src/app/meinimpact_app.dart';
import 'src/core/network/api_client.dart';
import 'src/core/profile/user_profile_store.dart';
import 'src/core/security/token_store.dart';
import 'src/features/feed/data/remote_action_repository.dart';

// Base URL for local development. Overridden in release builds via
// --dart-define=MEINIMPACT_API_BASE_URL=... (see .github/workflows/app.yml)
// — this was previously hardcoded and silently ignored the dart-define,
// so every deployed build tried to reach the developer's own localhost.
// Use http://10.0.2.2:8000/ when running on an Android emulator.
const _kBaseUrl = String.fromEnvironment(
  'MEINIMPACT_API_BASE_URL',
  defaultValue: 'http://localhost:8000/',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(
    baseUrl: Uri.parse(_kBaseUrl),
    tokenStore: tokenStore,
  );

  try {
    await apiClient.createAnonymousSession(
      installationId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      appVersion: '0.1.2',
    );
  } catch (e) {
    debugPrint('Session creation failed: $e');
  }

  final profileStore = UserProfileStore();
  final initialProfile = await profileStore.load();

  runApp(
    MeinImpactApp.withProfile(
      actionRepository: RemoteActionRepository(apiClient),
      profileStore: profileStore,
      initialProfile: initialProfile,
    ),
  );
}
