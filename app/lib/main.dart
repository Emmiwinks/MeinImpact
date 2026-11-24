import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app/meinimpact_app.dart';
import 'src/core/config/app_config.dart';
import 'src/core/feedback/beta_feedback.dart';
import 'src/core/network/api_client.dart';
import 'src/core/profile/user_profile_store.dart';
import 'src/core/security/installation_id_store.dart';
import 'src/core/security/token_store.dart';
import 'src/core/usage/usage.dart';
import 'src/features/feed/data/dismissed_cards_store.dart';
import 'src/features/feed/data/hand_hints.dart';
import 'src/features/feed/data/remote_opportunity_repository.dart';
import 'src/features/notifications/notifications.dart';
import 'src/features/tracking/data/action_log_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(
    baseUrl: Uri.parse(kApiBaseUrl),
    tokenStore: tokenStore,
  );

  // Not awaited: the app starts at once and shows its own loading state.
  // Requests wait for this session, and get a new one if it failed.
  unawaited(
    apiClient
        .createAnonymousSession(
          installationId: await const InstallationIdStore().load(),
          appVersion: kAppVersion,
        )
        .catchError((Object e) => debugPrint('Session creation failed: $e')),
  );

  Usage.current = Usage(
    send: (event) => apiClient.postJson('/v1/usage', {'event': event}),
  );
  BetaFeedback.current = BetaFeedback(post: apiClient.postJson);
  final repository = RemoteOpportunityRepository(apiClient);
  Notifications.current = Notifications.forPlatform(repository);
  unawaited(Notifications.current.start());

  final profileStore = UserProfileStore();
  final initialProfile = await profileStore.load();
  const actionLogStore = ActionLogStore();
  final initialActionLog = await actionLogStore.load();
  const dismissedStore = DismissedCardsStore();
  final initialDismissed = await dismissedStore.load();
  HandHints.current = await HandHints.load();

  runApp(
    MeinImpactApp.withProfile(
      opportunityRepository: repository,
      profileStore: profileStore,
      initialProfile: initialProfile,
      actionLogStore: actionLogStore,
      initialActionLog: initialActionLog,
      dismissedStore: dismissedStore,
      initialDismissed: initialDismissed,
    ),
  );
}

// The bundled fonts are under the SIL Open Font License, which asks that
// the licence ships with them; it shows on the system licence page.
void _registerFontLicenses() {
  for (final (family, file) in [
    ('Unbounded', 'Unbounded-OFL.txt'),
    ('Albert Sans', 'AlbertSans-OFL.txt'),
  ]) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        [family],
        await rootBundle.loadString('assets/fonts/$file'),
      );
    });
  }
}
