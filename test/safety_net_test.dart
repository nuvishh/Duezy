import 'package:duezy/models/reminder.dart';
import 'package:duezy/services/safety_net.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Reminder _reminder({
  required String id,
  required DateTime dueDate,
  int remindBeforeDays = 0,
  TimeOfDay remindAt = const TimeOfDay(hour: 9, minute: 0),
  bool done = false,
}) =>
    Reminder(
      id: id,
      title: id,
      category: ReminderCategory.other,
      dueDate: dueDate,
      remindBeforeDays: remindBeforeDays,
      remindAt: remindAt,
      done: done,
    );

void main() {
  group('Reminder.fireTime', () {
    test('on-the-day reminder fires at due date + time', () {
      final r = _reminder(
        id: 'a',
        dueDate: DateTime(2026, 11, 13),
        remindAt: const TimeOfDay(hour: 22, minute: 18),
      );
      expect(
        r.fireTime(now: DateTime(2026, 11, 13, 22, 13)),
        DateTime(2026, 11, 13, 22, 18),
      );
    });

    test('1-day-before reminder fires the day before', () {
      final r = _reminder(
        id: 'b',
        dueDate: DateTime(2026, 11, 13),
        remindBeforeDays: 1,
        remindAt: const TimeOfDay(hour: 9, minute: 0),
      );
      expect(
        r.fireTime(now: DateTime(2026, 11, 12, 8, 0)),
        DateTime(2026, 11, 12, 9, 0),
      );
    });

    test('passed days-before slot falls back to the due day', () {
      final r = _reminder(
        id: 'c',
        dueDate: DateTime(2026, 11, 13),
        remindBeforeDays: 1,
        remindAt: const TimeOfDay(hour: 9, minute: 0),
      );
      // Created 10:00 on the due day: yesterday 09:00 already passed.
      expect(
        r.fireTime(now: DateTime(2026, 11, 13, 10, 0)),
        DateTime(2026, 11, 13, 9, 0),
      );
    });
  });

  group('SafetyNetService.dueNow', () {
    final now = DateTime(2026, 11, 13, 22, 30);

    test('fires a reminder due 30 minutes ago', () {
      final r = _reminder(
        id: 'due',
        dueDate: DateTime(2026, 11, 13),
        remindAt: const TimeOfDay(hour: 22, minute: 0),
      );
      expect(SafetyNetService.dueNow([r], now, {}), [r]);
    });

    test('skips a reminder due in the future', () {
      final r = _reminder(
        id: 'future',
        dueDate: DateTime(2026, 11, 14),
        remindAt: const TimeOfDay(hour: 9, minute: 0),
      );
      expect(SafetyNetService.dueNow([r], now, {}), isEmpty);
    });

    test('skips a reminder due 2 minutes ago (alarm grace)', () {
      final r = _reminder(
        id: 'fresh',
        dueDate: DateTime(2026, 11, 13),
        remindAt: const TimeOfDay(hour: 22, minute: 28),
      );
      expect(SafetyNetService.dueNow([r], now, {}), isEmpty);
    });

    test('skips a reminder due 25 hours ago (stale window)', () {
      final r = _reminder(
        id: 'stale',
        dueDate: DateTime(2026, 11, 12),
        remindAt: const TimeOfDay(hour: 21, minute: 0),
      );
      expect(SafetyNetService.dueNow([r], now, {}), isEmpty);
    });

    test('skips an already-flagged reminder', () {
      final r = _reminder(
        id: 'flagged',
        dueDate: DateTime(2026, 11, 13),
        remindAt: const TimeOfDay(hour: 22, minute: 0),
      );
      expect(
        SafetyNetService.dueNow(
            [r], now, {SafetyNetService.flagKey(r)}),
        isEmpty,
      );
    });

    test('skips a done reminder', () {
      final r = _reminder(
        id: 'done',
        dueDate: DateTime(2026, 11, 13),
        remindAt: const TimeOfDay(hour: 22, minute: 0),
        done: true,
      );
      expect(SafetyNetService.dueNow([r], now, {}), isEmpty);
    });

    test('flags are per occurrence (same id, new due date)', () {
      final old = _reminder(
        id: 'same',
        dueDate: DateTime(2026, 11, 13),
        remindAt: const TimeOfDay(hour: 22, minute: 0),
      );
      final next = _reminder(
        id: 'same',
        dueDate: DateTime(2026, 11, 14),
        remindAt: const TimeOfDay(hour: 22, minute: 0),
      );
      final flagged = {SafetyNetService.flagKey(old)};
      expect(
        SafetyNetService.dueNow([next], DateTime(2026, 11, 14, 22, 30),
            flagged),
        [next],
      );
    });
  });
}
