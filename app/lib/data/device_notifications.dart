import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../state/reminders.dart';

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

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }
}
