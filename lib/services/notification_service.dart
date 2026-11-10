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
    // Device timezone: try the abbreviation map first ("IST" ->
    // Asia/Kolkata), else pick any tz location whose current UTC
    // offset matches the device. (A dedicated timezone plugin was
    // dropped: flutter_native_timezone 2.0.0 has no Android namespace
    // and fails to configure under AGP 9.2.)
    try {
      final mapped = _tzName(DateTime.now().timeZoneName);
      if (mapped != 'UTC') {
        tz.setLocalLocation(tz.getLocation(mapped));
      } else {
        final offset = DateTime.now().timeZoneOffset.inSeconds;
        final match = tz.timeZoneDatabase.locations.values.firstWhere(
          (loc) => loc.currentTimeZone.offset == offset,
          orElse: () => tz.UTC,
        );
        tz.setLocalLocation(match);
      }
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

  // Stable notification id derived from the reminder's UUID.
  // String.hashCode is NOT stable across app launches (Dart randomises
  // it per run), so using it meant cancel() never cancelled the right
  // pending notification after a restart, and rescheduleAll() kept
  // adding stale duplicates instead of replacing the old one.
  int _notifId(String reminderId) {
    final hex = reminderId.replaceAll('-', '');
    final v = int.tryParse(
      hex.substring(0, hex.length >= 8 ? 8 : hex.length),
      radix: 16,
    );
    return (v ?? 0) & 0x7fffffff;
  }

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
    if (when.isBefore(DateTime.now())) {
      // Chosen time already passed (e.g. saved at 3:21 for 3:20) —
      // fire a minute from now instead of silently dropping it.
      when = DateTime.now().add(const Duration(minutes: 1));
    }

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
    // Schedule by instant, not by wall-clock components: `when` is a
    // local DateTime whose millisecondsSinceEpoch is the true instant.
    // TZDateTime.from(when, tz.local) interpreted the components in
    // tz.local — if tz.local is wrong (e.g. UTC), every reminder
    // fired hours late, while the relative +1-min test still worked.
    await _plugin.zonedSchedule(
      _notifId(r.id),
      'Due ${r.remindBeforeDays == 0 ? 'today' : 'in ${r.remindBeforeDays}d'}: ${r.title}',
      '${r.category.label}$amount',
      tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.local, when.millisecondsSinceEpoch),
      details,
      androidScheduleMode: mode,
    );
  }

  Future<void> cancel(Reminder r) async {
    if (!_ready) return;
    await _plugin.cancel(_notifId(r.id));
  }

  /// IANA name of the timezone alarms are scheduled in (debug aid).
  String localTimeZoneName() => tz.local.name;

  /// Titles of notifications currently registered with the OS.
  Future<List<String>> pendingScheduled() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((p) => p.title ?? '(no title)').toList();
  }

  /// Immediate test notification — proves the channel can show at all.
  Future<void> showTestNotification() async {
    await _plugin.show(
      999998,
      'Duezy test',
      'Immediate test — if you see this, notifications can show.',
      _testDetails,
    );
  }

  /// Test notification scheduled 1 minute ahead — proves alarms fire.
  Future<void> scheduleTestNotification() async {
    final when = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1));
    try {
      await _plugin.zonedSchedule(
        999997,
        'Duezy test (scheduled)',
        'Scheduled 1 minute ahead — if this appears, scheduled alarms work.',
        when,
        _testDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        999997,
        'Duezy test (scheduled)',
        'Scheduled 1 minute ahead — if this appears, scheduled alarms work.',
        when,
        _testDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static const _testDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'duezy_reminders',
      'Due date reminders',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

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
