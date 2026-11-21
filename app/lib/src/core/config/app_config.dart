import 'package:flutter/foundation.dart';

// --dart-define=MEINIMPACT_API_BASE_URL=... wins (see
// .github/workflows/app.yml). Without it, release builds use the deployed
// API and debug builds the local one, so a release build can never ship
// pointing at localhost. Use http://10.0.2.2:8000/ on an Android emulator.
const _kConfiguredBaseUrl = String.fromEnvironment('MEINIMPACT_API_BASE_URL');

/// The API, for the app and its background check alike.
const kApiBaseUrl = _kConfiguredBaseUrl != ''
    ? _kConfiguredBaseUrl
    : kReleaseMode
        ? 'https://meinimpact-api.fly.dev/'
        : 'http://localhost:8000/';

/// Sent with each anonymous session.
const kAppVersion = '0.1.2';
