import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../state/reminders.dart';
import 'push_messages.dart';

/// The phone's notifications, behind a boundary so screens can be tested
/// without them. Reminders are made on the phone: nothing is sent anywhere.
abstract interface class DeviceNotifications {
  /// False where notifications are not built, so no switch is offered.
  bool get available;

  /// Whether the phone lets the app show notifications right now. The user
  /// can turn them off in the phone's settings at any time.
  Future<bool> allowed();

  /// Asks once (Android 13+ and iOS); later calls return the answer given.
  Future<bool> requestPermission();

  /// Makes [reminders] the phone's pending reminders, cancelling any others.
  Future<void> replaceReminders(List<Reminder> reminders);

  /// Shows a push that arrived while the app is open, which the phone does
  /// not show by itself then.
  Future<void> show(PushNotice notice);

  /// The payload of a notification the user tapped while the app was open.
  Stream<String> get taps;

  /// The payload of the notification that opened the app, if one did.
  Future<String?> launchPayload();
}

/// Builds without notifications, and the default in tests.
class NoDeviceNotifications implements DeviceNotifications {
  const NoDeviceNotifications();

  @override
  bool get available => false;

  @override
  Future<bool> allowed() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceReminders(List<Reminder> reminders) async {}

  @override
  Future<void> show(PushNotice notice) async {}

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> launchPayload() async => null;
}

/// flutter_local_notifications on Android and iOS.
class PluginDeviceNotifications implements DeviceNotifications {
  PluginDeviceNotifications._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();

  static const _channel = AndroidNotificationDetails(
    'match_reminders',
    'Match reminders',
    channelDescription: 'Before your matches and the ones you asked to be reminded of',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF6FAE29), // AppColors.brandGreen: tints the small icon
  );

  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
  );

  /// Pushes: live matches, teams and cups. Its id is also the default
  /// channel in AndroidManifest.xml, so pushes the phone shows by itself land
  /// in the same place.
  static const updatesChannelId = 'updates';

  static const _updates = AndroidNotificationDetails(
    updatesChannelId,
    'Match and team updates',
    channelDescription: 'Matches you follow, your teams and your cups',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF6FAE29),
  );

  /// Starts the plugin without asking for permission: that waits for the
  /// moment the user turns reminders on.
  static Future<PluginDeviceNotifications> start() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final notifications = PluginDeviceNotifications._(plugin);
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_bnp'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload case final payload?) notifications._taps.add(payload);
      },
    );
    // Made now so a push that arrives before the app ever showed one still
    // has its channel.
    await notifications._android?.createNotificationChannel(const AndroidNotificationChannel(
      updatesChannelId,
      'Match and team updates',
      description: 'Matches you follow, your teams and your cups',
      importance: Importance.high,
    ));
    return notifications;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  bool get available => true;

  @override
  Future<bool> allowed() async {
    try {
      if (_android case final android?) return await android.areNotificationsEnabled() ?? false;
      if (_ios case final ios?) return (await ios.checkPermissions())?.isEnabled ?? false;
    } on PlatformException catch (e) {
      debugPrint('Could not read the notification permission: $e');
    }
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (_android case final android?) return await android.requestNotificationsPermission() ?? false;
      if (_ios case final ios?) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } on PlatformException catch (e) {
      debugPrint('Could not ask for the notification permission: $e');
    }
    return false;
  }

  @override
  Future<void> replaceReminders(List<Reminder> reminders) async {
    final wanted = {for (final r in reminders) r.id};
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (isReminderPayload(pending.payload) && !wanted.contains(pending.id)) {
        await _plugin.cancel(id: pending.id);
      }
    }
    for (final r in reminders) {
      // Inexact is enough for a reminder an hour out, and needs no
      // exact-alarm permission. A UTC instant is right in any time zone.
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        payload: r.payload,
      );
    }
  }

  /// Shown pushes take ids from a base of their own, so one never replaces
  /// a reminder; cycling through 1000 keeps the tray from filling forever.
  int _shown = 0;

  @override
  Future<void> show(PushNotice notice) => _plugin.show(
        id: 0x40000000 + (_shown++ % 1000),
        title: notice.title,
        body: notice.body,
        notificationDetails: const NotificationDetails(android: _updates, iOS: DarwinNotificationDetails()),
        payload: notice.data['open'],
      );

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }
}
