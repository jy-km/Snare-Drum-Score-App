import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'practice_schedule.dart';

/// Scheduled practice reminders as real phone notifications
/// (flutter_local_notifications).
class LocalReminderNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialized;

  static const _channel = AndroidNotificationDetails(
    'practice_reminders',
    'Practice reminders',
    channelDescription: 'Practice sessions you scheduled from your recordings',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Sets up the plugin and the phone's time zone (scheduled times are
  /// wall-clock times in it). Safe to call more than once.
  Future<void> initialize() => _initialized ??= _initialize();

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      // Falls back to UTC offsets as given; only matters across a DST change.
      debugPrint('Could not read the phone\'s time zone: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked for when a session is first scheduled, not at
        // launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> ensurePermission() async {
    await initialize();
    if (Platform.isAndroid) return await _android?.requestNotificationsPermission() ?? true;
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true, badge: true) ??
          false;
    }
    return true;
  }

  @override
  Future<bool> schedule(ScheduledPractice practice, {required String body}) async {
    await initialize();
    // On-the-minute delivery needs Android's "alarms & reminders"
    // permission, off by default on recent Android; without it the phone
    // may deliver a little late to save battery.
    final exact = Platform.isAndroid ? await _android?.canScheduleExactNotifications() ?? false : true;
    final now = DateTime.now();

    Future<void> notifyAt(int id, DateTime first, DateTimeComponents? repeatOn) =>
        _plugin.zonedSchedule(
          id: id,
          scheduledDate: tz.TZDateTime.from(first, tz.local),
          notificationDetails: const NotificationDetails(
            android: _channel,
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode:
              exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
          // The phone repeats the notification itself: every day at the
          // same time, or every week on the same day and time.
          matchDateTimeComponents: repeatOn,
          title: 'Time to practice ${practice.trackTitle}',
          body: body,
        );

    switch (practice.repeat) {
      case PracticeRepeat.once:
        await notifyAt(practice.notificationIds.single, practice.onceAt!, null);
      case PracticeRepeat.daily:
        await notifyAt(
          practice.notificationIds.single,
          practice.nextOccurrence(now),
          DateTimeComponents.time,
        );
      case PracticeRepeat.weekly:
        // One weekly-repeating notification per chosen day.
        final ids = practice.notificationIds;
        for (var i = 0; i < practice.weekdays.length; i++) {
          await notifyAt(
            ids[i],
            practice.nextOnWeekday(practice.weekdays[i], now),
            DateTimeComponents.dayOfWeekAndTime,
          );
        }
    }
    return exact;
  }

  @override
  Future<void> cancel(ScheduledPractice practice) async {
    await initialize();
    for (final id in practice.notificationIds) {
      await _plugin.cancel(id: id);
    }
  }

  @override
  Future<void> requestExactTiming() async {
    await initialize();
    await _android?.requestExactAlarmsPermission();
  }
}
