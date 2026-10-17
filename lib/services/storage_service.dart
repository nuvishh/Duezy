import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/reminder.dart';

/// Hive-backed storage. Reminders are kept as plain maps — no codegen needed.
class StorageService {
  static const _boxName = 'reminders';
  static const _uuid = Uuid();

  late Box _box;
  bool _ready = false;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
    _ready = true;
  }

  bool get isReady => _ready;

  /// Raw listenable for reactive UI.
  ValueListenable<Box> listenable() => _box.listenable();

  String newId() => _uuid.v4();

  List<Reminder> all() {
    final out = <Reminder>[];
    for (final v in _box.values) {
      try {
        out.add(Reminder.fromMap(Map<String, dynamic>.from(v as Map)));
      } catch (_) {
        // Skip corrupt entries instead of crashing.
      }
    }
    out.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return out;
  }

  /// Active reminders (not done), sorted by due date.
  List<Reminder> active() => all().where((r) => !r.done).toList();

  /// Done / paid history, newest first.
  List<Reminder> history() {
    final h = all().where((r) => r.done).toList();
    h.sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return h;
  }

  Future<void> save(Reminder r) async => _box.put(r.id, r.toMap());

  Future<void> delete(String id) async => _box.delete(id);

  /// Marks [r] done. When it repeats, a fresh occurrence is created
  /// carrying the schedule forward.
  Future<Reminder?> markDone(Reminder r) async {
    await save(r.copyWith(done: true));
    final next = r.repeat.nextFrom(r.dueDate);
    if (next == null) return null;
    final followUp = Reminder(
      id: newId(),
      title: r.title,
      category: r.category,
      amount: r.amount,
      dueDate: next,
      repeat: r.repeat,
      remindBeforeDays: r.remindBeforeDays,
      notes: r.notes,
    );
    await save(followUp);
    return followUp;
  }

  double totalDueThisMonth() {
    final now = DateTime.now();
    return active()
        .where((r) =>
            r.dueDate.year == now.year &&
            r.dueDate.month == now.month &&
            r.amount != null)
        .fold(0.0, (sum, r) => sum + (r.amount ?? 0));
  }

  int overdueCount() => active().where((r) => r.isOverdue).length;
}
