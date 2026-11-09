import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// Local scheduled notifications — no server, works offline.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    tzdata.initializeTimeZones();
    // Best-effort local timezone name; falls back to UTC.
    try {
      final name = DateTime.now().timeZoneName;
      tz.setLocalLocation(tz.getLocation(_tzName(name)));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    // Exact alarms: the manifest already declares SCHEDULE_EXACT_ALARM +
    // USE_EXACT_ALARM; ask the system to grant it so reminders fire on
    // time instead of being batched by Doze.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _ready = true;
  }

  /// True when the user has allowed notifications for Duezy.
  /// (On Android < 13 this is always granted at install.)
  Future<bool> notificationsEnabled() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Ask for notification permission in-app (Android 13+ system dialog).
  Future<bool> requestNotifications() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// True when the app may schedule exact alarms, so reminders fire on
  /// time instead of being batched by Doze. On iOS / non-Android this
  /// does not apply, so it reports true; a null answer is treated as
  /// granted rather than raising a false alarm.
  Future<bool> exactAlarmsEnabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final ok = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.canScheduleExactNotifications();
      return ok ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Ask for exact-alarm permission in-app (opens the system page).
  Future<bool> requestExactAlarms() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final ok = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
      return ok ?? true;
    } catch (_) {
      return false;
    }
  }

  /// True when battery optimisation is ignored for Duezy, so Doze /
  /// MIUI cannot delay or kill scheduled reminders. Not applicable on
  /// iOS, so it reports true there; errors report true rather than
  /// raising a false alarm.
  Future<bool> batteryOptimizationsIgnored() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Ask to ignore battery optimisations (opens the system dialog/page).
  Future<bool> requestBatteryExemption() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final status =
          await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system App info page for Duezy, so the user can turn
  /// notifications on when permission was denied.
  Future<bool> openSettings() => openAppSettings();

  /// Very small mapping; unknown zones fall back to UTC via [init] catch.
  String _tzName(String local) {
    // Most devices report abbreviations like "IST". Map the common one.
    if (local == 'IST') return 'Asia/Kolkata';
    return 'UTC';
  }

  int _notifId(String reminderId) => reminderId.hashCode & 0x7fffffff;

  Future<void> schedule(Reminder r) async {
    if (!_ready || r.done) return;
    var when = DateTime(
      r.dueDate.year,
      r.dueDate.month,
      r.dueDate.day,
      r.remindAt.hour,
      r.remindAt.minute,
    ).subtract(Duration(days: r.remindBeforeDays));
    if (when.isBefore(DateTime.now())) {
      // The "days before" slot already passed (e.g. a reminder created
      // today for today with "1 day before") — fall back to the due day
      // at the chosen time instead of silently dropping the notification.
      when = DateTime(
        r.dueDate.year,
        r.dueDate.month,
        r.dueDate.day,
        r.remindAt.hour,
        r.remindAt.minute,
      );
    }
    if (when.isBefore(DateTime.now())) return;

    final amount = r.amount != null ? ' — ₹${_fmtAmount(r.amount!)}' : '';
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'duezy_reminders',
        'Due date reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      // Exact alarm so the reminder fires on time, not batched by Doze.
      await _scheduleWithMode(r, when, amount, details,
          AndroidScheduleMode.exactAllowWhileIdle);
    } catch (_) {
      // Exact alarms not granted on this device — fall back to inexact.
      await _scheduleWithMode(
          r, when, amount, details, AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  Future<void> _scheduleWithMode(
    Reminder r,
    DateTime when,
    String amount,
    NotificationDetails details,
    AndroidScheduleMode mode,
  ) async {
    await _plugin.zonedSchedule(
      _notifId(r.id),
      'Due ${r.remindBeforeDays == 0 ? 'today' : 'in ${r.remindBeforeDays}d'}: ${r.title}',
      '${r.category.label}$amount',
      tz.TZDateTime.from(when, tz.local),
      details,
      androidScheduleMode: mode,
    );
  }

  Future<void> cancel(Reminder r) async {
    if (!_ready) return;
    await _plugin.cancel(_notifId(r.id));
  }

  Future<void> rescheduleAll(Iterable<Reminder> reminders) async {
    if (!_ready) return;
    for (final r in reminders) {
      await cancel(r);
      await schedule(r);
    }
  }

  String _fmtAmount(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @visibleForTesting
  void debugMarkReady() => _ready = true;
}
