import 'package:flutter/material.dart';

/// Category of a reminder — drives icon, color and grouping.
enum ReminderCategory {
  subscription,
  loan,
  warranty,
  document,
  other,
}

extension ReminderCategoryX on ReminderCategory {
  String get label => switch (this) {
        ReminderCategory.subscription => 'Subscription',
        ReminderCategory.loan => 'Loan EMI',
        ReminderCategory.warranty => 'Warranty',
        ReminderCategory.document => 'Document',
        ReminderCategory.other => 'Other',
      };

  IconData get icon => switch (this) {
        ReminderCategory.subscription => Icons.autorenew_rounded,
        ReminderCategory.loan => Icons.account_balance_rounded,
        ReminderCategory.warranty => Icons.verified_user_rounded,
        ReminderCategory.document => Icons.description_rounded,
        ReminderCategory.other => Icons.notifications_rounded,
      };

  Color get color => switch (this) {
        ReminderCategory.subscription => const Color(0xFF7C6CFF),
        ReminderCategory.loan => const Color(0xFFFF9F43),
        ReminderCategory.warranty => const Color(0xFF2ED573),
        ReminderCategory.document => const Color(0xFF54C7F7),
        ReminderCategory.other => const Color(0xFF9AA5B1),
      };
}

/// How a reminder repeats after its due date passes.
enum RepeatInterval {
  none,
  monthly,
  quarterly,
  yearly,
}

extension RepeatIntervalX on RepeatInterval {
  String get label => switch (this) {
        RepeatInterval.none => 'One-time',
        RepeatInterval.monthly => 'Monthly',
        RepeatInterval.quarterly => 'Quarterly',
        RepeatInterval.yearly => 'Yearly',
      };

  /// Next due date after [from], or null when non-repeating.
  DateTime? nextFrom(DateTime from) {
    switch (this) {
      case RepeatInterval.none:
        return null;
      case RepeatInterval.monthly:
        return DateTime(from.year, from.month + 1, from.day);
      case RepeatInterval.quarterly:
        return DateTime(from.year, from.month + 3, from.day);
      case RepeatInterval.yearly:
        return DateTime(from.year + 1, from.month, from.day);
    }
  }
}

/// A single due-date reminder. Stored as a plain map in Hive (no codegen).
class Reminder {
  final String id;
  String title;
  ReminderCategory category;
  double? amount;
  DateTime dueDate;
  RepeatInterval repeat;
  int remindBeforeDays;
  TimeOfDay remindAt;
  String? notes;
  bool done;
  DateTime createdAt;

  Reminder({
    required this.id,
    required this.title,
    required this.category,
    this.amount,
    required this.dueDate,
    this.repeat = RepeatInterval.none,
    this.remindBeforeDays = 1,
    this.remindAt = const TimeOfDay(hour: 9, minute: 0),
    this.notes,
    this.done = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isOverdue =>
      !done &&
      dueDate.isBefore(DateTime(DateTime.now().year, DateTime.now().month,
          DateTime.now().day));

  bool get isDueToday {
    final now = DateTime.now();
    return !done &&
        dueDate.year == now.year &&
        dueDate.month == now.month &&
        dueDate.day == now.day;
  }

  /// The instant this reminder's notification should fire: the due date
  /// at [remindAt], pulled back by [remindBeforeDays]. If that slot
  /// already passed (e.g. created today for today with "1 day before"),
  /// the due day at the chosen time is used instead. Callers that
  /// schedule an alarm add their own "already past → soon" fallback;
  /// the safety net uses this raw instant to tell a missed reminder
  /// from one that is not due yet.
  DateTime fireTime({DateTime? now}) {
    final at = now ?? DateTime.now();
    var when = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
      remindAt.hour,
      remindAt.minute,
    ).subtract(Duration(days: remindBeforeDays));
    if (when.isBefore(at)) {
      when = DateTime(
        dueDate.year,
        dueDate.month,
        dueDate.day,
        remindAt.hour,
        remindAt.minute,
      );
    }
    return when;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'category': category.index,
        'amount': amount,
        'dueDate': dueDate.toIso8601String(),
        'repeat': repeat.index,
        'remindBeforeDays': remindBeforeDays,
        'remindAtMinutes': remindAt.hour * 60 + remindAt.minute,
        'notes': notes,
        'done': done,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Reminder.fromMap(Map<String, dynamic> m) => Reminder(
        id: m['id'] as String,
        title: m['title'] as String,
        category: ReminderCategory.values[m['category'] as int],
        amount: (m['amount'] as num?)?.toDouble(),
        dueDate: DateTime.parse(m['dueDate'] as String),
        repeat: RepeatInterval.values[m['repeat'] as int? ?? 0],
        remindBeforeDays: m['remindBeforeDays'] as int? ?? 1,
        remindAt: _timeOfDay(m['remindAtMinutes'] as int? ?? 540),
        notes: m['notes'] as String?,
        done: m['done'] as bool? ?? false,
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? ''),
      );

  Reminder copyWith({
    String? title,
    ReminderCategory? category,
    double? amount,
    DateTime? dueDate,
    RepeatInterval? repeat,
    int? remindBeforeDays,
    TimeOfDay? remindAt,
    String? notes,
    bool? done,
  }) =>
      Reminder(
        id: id,
        title: title ?? this.title,
        category: category ?? this.category,
        amount: amount ?? this.amount,
        dueDate: dueDate ?? this.dueDate,
        repeat: repeat ?? this.repeat,
        remindBeforeDays: remindBeforeDays ?? this.remindBeforeDays,
        remindAt: remindAt ?? this.remindAt,
        notes: notes ?? this.notes,
        done: done ?? this.done,
        createdAt: createdAt,
      );
}

TimeOfDay _timeOfDay(int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
