import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reminder.dart';

/// One row in the reminder list: icon, title, meta, amount, due chip.
class ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onToggleDone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onToggleDone,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final cat = r.category;
    final dueLabel = _dueLabel(r);
    final dueColor = r.isOverdue
        ? Colors.redAccent
        : r.isDueToday
            ? Colors.orangeAccent
            : Colors.grey;

    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // we handle deletion ourselves (with undo outside)
      },
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: r.isOverdue
              ? const BorderSide(color: Colors.redAccent, width: 1)
              : BorderSide.none,
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: cat.color.withValues(alpha: 0.15),
            child: Icon(cat.icon, color: cat.color),
          ),
          title: Text(
            r.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: r.done ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cat.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: cat.color,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.schedule_rounded, size: 13, color: dueColor),
                  const SizedBox(width: 4),
                  Text(
                    dueLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: dueColor,
                        fontWeight: FontWeight.w600),
                  ),
                  if (r.repeat != RepeatInterval.none) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.repeat_rounded,
                        size: 13, color: Colors.grey.shade600),
                  ],
                ],
              ),
              if (r.notes?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    r.notes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.amount != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '₹${_fmt(r.amount!)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              Checkbox(
                value: r.done,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                onChanged: (_) => onToggleDone(),
              ),
            ],
          ),
          onTap: onEdit,
          onLongPress: onEdit,
        ),
      ),
    );
  }

  String _dueLabel(Reminder r) {
    if (r.done) return 'Done';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(r.dueDate.year, r.dueDate.month, r.dueDate.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return 'Overdue by ${-diff}d';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff <= 7) return 'In $diff days';
    return DateFormat('d MMM y').format(r.dueDate);
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
