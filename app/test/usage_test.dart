import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meinimpact/src/core/usage/usage.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  // Each test builds a fresh Usage, as a fresh app start would.
  Usage usageAt(DateTime now, List<String> sent, {bool offline = false}) =>
      Usage(
        send: (event) async {
          if (offline) throw Exception('offline');
          sent.add(event);
        },
        now: () => now,
      );

  test('says active once per day and once per week', () async {
    final sent = <String>[];
    // Wednesday, Thursday, Thursday again, then next Monday
    await usageAt(DateTime(2026, 11, 18, 9), sent).markActive();
    await usageAt(DateTime(2026, 11, 19, 8), sent).markActive();
    await usageAt(DateTime(2026, 11, 19, 20), sent).markActive();
    await usageAt(DateTime(2026, 11, 23, 7), sent).markActive();

    expect(sent, [
      'active_day',
      'active_week',
      'active_day',
      'active_day',
      'active_week',
    ]);
  });

  test('a resumed app does not count again the same day', () async {
    final sent = <String>[];
    final usage = usageAt(DateTime(2026, 11, 18, 9), sent);

    await usage.markActive();
    await usage.markActive();

    expect(sent, ['active_day', 'active_week']);
  });

  test('offline it tries again on the next start', () async {
    final sent = <String>[];
    await usageAt(DateTime(2026, 11, 18, 9), sent, offline: true).markActive();
    await usageAt(DateTime(2026, 11, 18, 10), sent).markActive();

    expect(sent, ['active_day', 'active_week']);
  });

  test('events go out by name and failures stay quiet', () async {
    final sent = <String>[];
    usageAt(DateTime(2026, 11, 18), sent).count(UsageEvent.cardTurned);
    usageAt(DateTime(2026, 11, 18), sent, offline: true)
        .count(UsageEvent.actionDone);
    await Future<void>.delayed(Duration.zero);

    expect(sent, ['card_turned']);
  });

  test('off by default', () async {
    await Usage.current.markActive();
    Usage.current.count(UsageEvent.actionDone);
  });
}
