import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _ready = true;
  }

  /// Very small mapping; unknown zones fall back to UTC via [init] catch.
  String _tzName(String local) {
    // Most devices report abbreviations like "IST". Map the common one.
    if (local == 'IST') return 'Asia/Kolkata';
    return 'UTC';
  }

  int _notifId(String reminderId) => reminderId.hashCode & 0x7fffffff;

  Future<void> schedule(Reminder r) async {
    if (!_ready || r.done) return;
    final when = DateTime(
      r.dueDate.year,
      r.dueDate.month,
      r.dueDate.day,
      9,
      0,
    ).subtract(Duration(days: r.remindBeforeDays));
    if (when.isBefore(DateTime.now())) return;

    final amount = r.amount != null ? ' — ₹${_fmtAmount(r.amount!)}' : '';
    await _plugin.zonedSchedule(
      _notifId(r.id),
      'Due ${r.remindBeforeDays == 0 ? 'today' : 'in ${r.remindBeforeDays}d'}: ${r.title}',
      '${r.category.label}$amount',
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'duezy_reminders',
          'Due date reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
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
