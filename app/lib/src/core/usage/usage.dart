import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What the app counts for the /admin page. Each event goes out by name
/// only; the server adds one to that day's count.
enum UsageEvent {
  onboardingDone('onboarding_done'),
  cardTurned('card_turned'),
  actionOpened('action_opened'),
  actionDone('action_done'),
  letterToMailApp('letter_to_mail_app'),
  impactOpened('impact_opened');

  const UsageEvent(this.wireName);

  final String wireName;
}

/// Anonymous usage counters. Nothing about the user, the device or an
/// action is sent, only the event's name. To count phones without an id,
/// the phone itself remembers whether it already said "used today" and
/// "used this week", and says each at most once.
///
/// Best effort throughout: offline, an event is lost and the app carries
/// on. Off (the default, so tests and demos send nothing) until `main` sets
/// [current].
class Usage {
  Usage({
    required Future<void> Function(String event) send,
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  })  : _send = send,
        _storage = storage ?? const FlutterSecureStorage(),
        _now = now ?? DateTime.now;

  Usage.off()
      : _send = null,
        _storage = null,
        _now = DateTime.now;

  static Usage current = Usage.off();

  static const _key = 'usage_active_v1';

  final Future<void> Function(String event)? _send;
  final FlutterSecureStorage? _storage;
  final DateTime Function() _now;
  // The day this run already checked, so resuming twice a day reads
  // nothing.
  String? _checkedDay;

  void count(UsageEvent event) {
    final send = _send;
    if (send == null) return;
    unawaited(send(event.wireName).catchError((Object _) {}));
  }

  /// Says "used today" and "used this week" once each per phone.
  Future<void> markActive() async {
    final send = _send;
    final storage = _storage;
    if (send == null || storage == null) return;
    final now = _now();
    final day = _isoDay(now);
    if (_checkedDay == day) return;
    _checkedDay = day;
    final week =
        _isoDay(DateTime(now.year, now.month, now.day - (now.weekday - 1)));
    try {
      final raw = await storage.read(key: _key);
      final said = raw == null
          ? <String, Object?>{}
          : jsonDecode(raw) as Map<String, Object?>;
      // Each remembered once sent, so an offline start tries again later
      // without counting twice.
      for (final (field, value, event) in [
        ('day', day, 'active_day'),
        ('week', week, 'active_week'),
      ]) {
        if (said[field] == value) continue;
        await send(event);
        said[field] = value;
        await storage.write(key: _key, value: jsonEncode(said));
      }
    } catch (error) {
      _checkedDay = null;
      debugPrint('Usage could not be counted: $error');
    }
  }

  static String _isoDay(DateTime moment) =>
      '${moment.year.toString().padLeft(4, '0')}-'
      '${moment.month.toString().padLeft(2, '0')}-'
      '${moment.day.toString().padLeft(2, '0')}';
}
