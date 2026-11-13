import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// WorkManager safety net.
///
/// On some MIUI/HyperOS devices the OS never delivers a scheduled alarm —
/// not even a setAlarmClock one — despite exact-alarms permission,
/// Autostart and "No restrictions" all being on (verified on the user's
/// Redmi 12 5G, 2026-11-13: v1.0.5 alarm pending in the system, never
/// fired). The alarm path stays primary — it is exact and works on most
/// devices. This net only catches what it missed: a periodic worker
/// (every 15 min, Android minimum) re-checks active reminders and shows
/// any due one directly with `show()`, which the immediate test proves
/// the OS will display.
///
/// Delivery can therefore be up to ~15–30 min late on an affected
/// device. That is far better than never, and on a healthy device the
/// net stays silent: it only fires for reminders whose fire time passed
/// at least [grace] ago, and never twice for the same occurrence.
class SafetyNetService {
  static const _flagPrefix = 'safetynet_notified_';

  /// Let the alarm have its moment before the net steps in.
  static const grace = Duration(minutes: 5);

  /// Do not flood the user with ancient overdue reminders after the
  /// phone was off for days; the home screen already lists them.
  static const window = Duration(hours: 24);

  final StorageService storage;
  final NotificationService notifications;

  SafetyNetService({required this.storage, required this.notifications});

  /// Pure selection: which active reminders the net should show [now].
  /// Kept pure (no plugins) so it is unit-testable.
  static List<Reminder> dueNow(
    List<Reminder> active,
    DateTime now,
    Set<String> flagged,
  ) {
    final out = <Reminder>[];
    for (final r in active) {
      if (r.done) continue;
      final fire = r.fireTime(now: now);
      if (fire.isAfter(now)) continue; // not due yet
      if (now.difference(fire) < grace) continue; // let the alarm fire
      if (now.difference(fire) > window) continue; // too stale to flood
      if (flagged.contains(flagKey(r))) continue; // already shown by net
      out.add(r);
    }
    return out;
  }

  /// One flag per reminder occurrence (a repeat's next occurrence gets
  /// a fresh id, and a re-dated reminder a fresh due date).
  static String flagKey(Reminder r) =>
      '${r.id}@${r.dueDate.year}-${r.dueDate.month}-${r.dueDate.day}';

  /// One worker run: show every due, unflagged reminder and flag it.
  Future<void> checkAndNotify() async {
    final prefs = await SharedPreferences.getInstance();
    final flagged = prefs
        .getKeys()
        .where((k) => k.startsWith(_flagPrefix))
        .map((k) => k.substring(_flagPrefix.length))
        .toSet();
    final active = storage.active();
    final due = dueNow(active, DateTime.now(), flagged);
    for (final r in due) {
      await notifications.showReminderNow(r);
      await prefs.setBool('$_flagPrefix${flagKey(r)}', true);
    }
    // Prune flags for reminders that no longer exist (deleted / done),
    // so the flag store does not grow forever.
    final liveIds = active.map((r) => r.id).toSet();
    for (final key in flagged) {
      if (!liveIds.contains(key.split('@').first)) {
        await prefs.remove('$_flagPrefix$key');
      }
    }
  }
}
