# MeinImpact App

Flutter client for MeinImpact.

## Stack

- Flutter.
- Dart.
- HTTPS JSON APIs.
- HTTPS streaming with SSE-formatted events.

## Local Development

Generate Flutter platform folders after installing Flutter:

```bash
flutter create --platforms=android,ios,web,windows,macos,linux .
flutter pub get
flutter run
```

The current scaffold uses a demo repository for the first UI screen. The API
client and remote repository are already separated for backend integration.

## Quality Gates

```bash
dart format --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --coverage
python ../tools/check_lcov.py coverage/lcov.info 95
```
