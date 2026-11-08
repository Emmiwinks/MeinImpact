import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app/meinimpact_app.dart';
import 'src/core/network/api_client.dart';
import 'src/core/profile/user_profile_store.dart';
import 'src/core/security/installation_id_store.dart';
import 'src/core/security/token_store.dart';
import 'src/features/feed/data/remote_opportunity_repository.dart';
import 'src/features/tracking/data/action_log_store.dart';

// --dart-define=MEINIMPACT_API_BASE_URL=... wins (see
// .github/workflows/app.yml). Without it, release builds use the deployed
// API and debug builds the local one, so a release build can never ship
// pointing at localhost. Use http://10.0.2.2:8000/ on an Android emulator.
const _kConfiguredBaseUrl = String.fromEnvironment('MEINIMPACT_API_BASE_URL');
const _kBaseUrl = _kConfiguredBaseUrl != ''
    ? _kConfiguredBaseUrl
    : kReleaseMode
        ? 'https://meinimpact-api.fly.dev/'
        : 'http://localhost:8000/';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(
    baseUrl: Uri.parse(_kBaseUrl),
    tokenStore: tokenStore,
  );

  try {
    await apiClient.createAnonymousSession(
      installationId: await const InstallationIdStore().load(),
      appVersion: '0.1.2',
    );
  } catch (e) {
    debugPrint('Session creation failed: $e');
  }

  final profileStore = UserProfileStore();
  final initialProfile = await profileStore.load();
  const actionLogStore = ActionLogStore();
  final initialActionLog = await actionLogStore.load();

  runApp(
    MeinImpactApp.withProfile(
      opportunityRepository: RemoteOpportunityRepository(apiClient),
      profileStore: profileStore,
      initialProfile: initialProfile,
      actionLogStore: actionLogStore,
      initialActionLog: initialActionLog,
    ),
  );
}
