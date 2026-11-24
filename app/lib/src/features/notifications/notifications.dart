import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/profile/user_profile_store.dart';
import '../../core/security/installation_id_store.dart';
import '../../core/security/token_store.dart';
import '../feed/data/dismissed_cards_store.dart';
import '../feed/data/remote_opportunity_repository.dart';
import '../feed/domain/opportunity.dart';
import '../feed/domain/opportunity_repository.dart';
import '../tracking/data/action_log_store.dart';
import '../tracking/data/starred_actions_store.dart';
import '../tracking/domain/action_log.dart';
import '../tracking/domain/impact_news.dart';
import 'data/notification_store.dart';
import 'domain/notification_planner.dart';
import 'domain/notification_state.dart';

/// The background check runs about this often; Android decides exactly
/// when, and less often when the phone sleeps or the app is rarely used.
const kCheckEvery = Duration(hours: 2);

/// The pool (about 200 KB) is loaded again after this long, the news on
/// every check.
const kPoolRefresh = Duration(hours: 12);

const _kWorkName = 'notification-check';

/// The "Ja, erledigt" button on "Abgeschickt?".
const kTookPartAction = 'took_part';

/// A tap on a notification or one of its buttons.
class NotificationTap {
  const NotificationTap({required this.kind, this.opportunityId, this.action});

  static NotificationTap? fromResponse(NotificationResponse? response) {
    final payload = response?.payload;
    if (payload == null) return null;
    try {
      final json = jsonDecode(payload) as Map<String, Object?>;
      final kind = NotificationKind.ofKey(json['kind'] as String);
      if (kind == null) return null;
      return NotificationTap(
        kind: kind,
        opportunityId: json['id'] as String?,
        action: response?.actionId,
      );
    } catch (_) {
      return null;
    }
  }

  final NotificationKind kind;
  final String? opportunityId;
  // The button tapped; null for the notification itself.
  final String? action;
}

/// Notifications, Android only for now. Everything is decided on the
/// device ([planNotifications]): the app loads the same pool and news as
/// everyone and shows its own notifications, so the server never learns
/// whom they concern. There are no push tokens.
///
/// Off (the default, so tests and the web build do nothing) until `main`
/// sets [current].
class Notifications {
  Notifications._(this._repository, this._plugin);

  Notifications.off()
      : _repository = null,
        _plugin = null;

  factory Notifications.forPlatform(OpportunityRepository repository) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Notifications.off();
    }
    return Notifications._(repository, FlutterLocalNotificationsPlugin());
  }

  static Notifications current = Notifications.off();

  final OpportunityRepository? _repository;
  final FlutterLocalNotificationsPlugin? _plugin;
  final _store = const NotificationStore();

  /// The last tap; the app opens what it is about.
  final taps = ValueNotifier<NotificationTap?>(null);

  // One check or change at a time, so none overwrites another's state.
  Future<void> _queue = Future.value();

  bool get available => _plugin != null;

  Future<void> start() async {
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      await _initialize(plugin, onTap: _onResponse);
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _onResponse(launch!.notificationResponse!);
      }
      await Workmanager().initialize(notificationWorker);
      await _scheduleWork();
      await opened();
    } catch (error) {
      debugPrint('Notifications could not start: $error');
    }
  }

  void _onResponse(NotificationResponse response) {
    final tap = NotificationTap.fromResponse(response);
    if (tap != null) taps.value = tap;
  }

  /// Whether the system lets the app show notifications.
  Future<bool> allowed() async =>
      await _android?.areNotificationsEnabled() ?? false;

  /// Shows the system's question, true once allowed. Once the user said no
  /// there, Android doesn't ask again (see [openSettings]).
  Future<bool> requestPermission() async {
    final android = _android;
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission() ?? false;
    await _scheduleWork();
    refresh();
    return granted;
  }

  /// The app's notification settings in Android: the switch for all of them
  /// and one per [NotificationChannel]. The app has no switches of its own.
  Future<void> openSettings() async {
    await _android?.openAppNotificationSettings();
  }

  Future<NotificationState> state() => _serial(_store.load);

  /// The app came to the front: Monday's notification is no longer needed
  /// that day.
  Future<void> opened() async {
    if (!available) return;
    await _change((s) => s.copyWith(lastOpenedAt: DateTime.now()));
    refresh();
  }

  /// The user turned [opportunity]'s card over, or left its site without
  /// "Fertig" ([openedSite]).
  void lookedAt(Opportunity opportunity, {bool openedSite = false}) {
    if (!available) return;
    unawaited(_lookedAt(opportunity, openedSite));
  }

  Future<void> _lookedAt(Opportunity opportunity, bool openedSite) async {
    // Nothing is kept for notifications that can't come.
    if (!await allowed()) return;
    await _change((s) {
      final now = DateTime.now();
      final before = s.lookedAt[opportunity.id];
      return s.copyWith(
        lookedAt: {
          ...s.lookedAt,
          opportunity.id: LookedAtCard(
            card: ActionLogEntry.fromOpportunity(
              opportunity,
              doneAt: now,
              via: ActionVia.inAppBrowser,
            ),
            at: openedSite ? now : before?.at ?? now,
            openedSite: openedSite || (before?.openedSite ?? false),
          ),
        },
      );
    });
    refresh();
  }

  /// The card behind "Abgeschickt?", for "Ja, erledigt"; null once gone.
  Future<ActionLogEntry?> lookedAtCard(String opportunityId) async {
    final state = await this.state();
    return state.lookedAt[opportunityId]?.card;
  }

  /// Plans again: after anything that changes what to notify about.
  void refresh() {
    final plugin = _plugin;
    final repository = _repository;
    if (plugin == null || repository == null) return;
    unawaited(
      _serial(() => _check(plugin, repository)).catchError(
        (Object error) => debugPrint('Notification check failed: $error'),
      ),
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin?.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  // Only with permission: without it there is nothing to check for.
  Future<void> _scheduleWork() async {
    if (await allowed()) {
      await Workmanager().registerPeriodicTask(
        _kWorkName,
        _kWorkName,
        frequency: kCheckEvery,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } else {
      await Workmanager().cancelByUniqueName(_kWorkName);
    }
  }

  Future<void> _change(
    NotificationState Function(NotificationState) change,
  ) =>
      _serial(() async => _store.save(change(await _store.load())));

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}

/// The background check, started by Android about every [kCheckEvery].
@pragma('vm:entry-point')
void notificationWorker() {
  Workmanager().executeTask((task, input) async {
    try {
      final api = ApiClient(
        baseUrl: Uri.parse(kApiBaseUrl),
        tokenStore: SecureTokenStore(),
      );
      await api.createAnonymousSession(
        installationId: await const InstallationIdStore().load(),
        appVersion: kAppVersion,
      );
      final plugin = FlutterLocalNotificationsPlugin();
      await _initialize(plugin);
      await _check(plugin, RemoteOpportunityRepository(api));
    } catch (error) {
      // Offline or the like: the next run tries again.
      debugPrint('Background notification check failed: $error');
    }
    return true;
  });
}

// "Nein" on "Abgeschickt?" only closes the notification.
@pragma('vm:entry-point')
void _onBackgroundResponse(NotificationResponse response) {}

Future<void> _initialize(
  FlutterLocalNotificationsPlugin plugin, {
  void Function(NotificationResponse)? onTap,
}) async {
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    ),
    onDidReceiveNotificationResponse: onTap,
    onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
  );
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  for (final channel in NotificationChannel.values) {
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channel.wire,
        channel.label,
        description: channel.description,
        enableVibration: false,
      ),
    );
  }
}

/// Loads what the app knows, plans and hands the result to the system.
Future<void> _check(
  FlutterLocalNotificationsPlugin plugin,
  OpportunityRepository repository,
) async {
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (!(await android?.areNotificationsEnabled() ?? false)) return;
  final profile = await const UserProfileStore().load();
  // Not before onboarding is done.
  if (profile == null) return;
  const store = NotificationStore();
  var state = await store.load();
  final now = DateTime.now();

  ImpactNewsFeed? news;
  try {
    news = await repository.impactNews();
  } catch (_) {
    // News wait for the next check.
  }
  List<Opportunity>? pool;
  final fetched = state.poolFetchedAt;
  if (fetched == null || now.difference(fetched) > kPoolRefresh) {
    try {
      pool = await repository.pool(kreis: profile.home?.kreis);
      state = state.copyWith(poolFetchedAt: now);
    } catch (_) {
      // Monday's notification stays as planned.
    }
  }

  // Channels the user switched off in Android, so they don't take a day's
  // place from another.
  final channels = await android?.getNotificationChannels() ?? const [];
  final off = {
    for (final channel in NotificationChannel.values)
      if (channels.any(
        (c) => c.id == channel.wire && c.importance == Importance.none,
      ))
        channel,
  };

  final plan = planNotifications(
    now: now,
    off: off,
    state: state,
    log: await const ActionLogStore().load(),
    starred: await const StarredActionsStore().load(),
    dismissed: await const DismissedCardsStore().load(),
    profile: profile,
    pool: pool,
    news: news,
  );
  for (final id in plan.cancel) {
    await plugin.cancel(id: id);
  }
  for (final p in plan.schedule) {
    await plugin.zonedSchedule(
      id: p.id,
      title: p.title,
      body: p.body,
      payload: _payload(p),
      scheduledDate: tz.TZDateTime.from(p.at, tz.UTC),
      notificationDetails: _details(p),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
  for (final p in plan.show) {
    await plugin.show(
      id: p.id,
      title: p.title,
      body: p.body,
      payload: _payload(p),
      notificationDetails: _details(p),
    );
  }
  await store.save(plan.state);
}

String _payload(PlannedNotification p) =>
    jsonEncode({'kind': p.kind.wire, 'id': p.opportunityId});

NotificationDetails _details(PlannedNotification p) {
  final channel = p.kind.channel;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      channel.wire,
      channel.label,
      enableVibration: false,
      // The user decided titles may show on the lock screen; private ones
      // are never named in the first place.
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(p.body),
      actions: p.kind == NotificationKind.tookPart
          ? const [
              AndroidNotificationAction(
                kTookPartAction,
                'Ja, erledigt',
                showsUserInterface: true,
              ),
              AndroidNotificationAction('not_yet', 'Nein'),
            ]
          : null,
    ),
  );
}
