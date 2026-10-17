import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reminder.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../widgets/reminder_card.dart';
import 'edit_reminder_screen.dart';

/// Home: summary header + grouped upcoming reminders.
class HomeScreen extends StatefulWidget {
  final StorageService storage;
  final NotificationService notifications;

  const HomeScreen({
    super.key,
    required this.storage,
    required this.notifications,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ReminderCategory? _filter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⏰ Duezy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'History',
            onPressed: _openHistory,
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: widget.storage.listenable(),
        builder: (context, _, __) {
          final all = widget.storage.active();
          final list = _filter == null
              ? all
              : all.where((r) => r.category == _filter).toList();
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCard(storage: widget.storage),
                const SizedBox(height: 12),
                _FilterRow(
                  selected: _filter,
                  onSelect: (c) => setState(() => _filter = c),
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  _EmptyState(onAdd: _addReminder)
                else
                  ..._grouped(list),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReminder,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Reminder'),
      ),
    );
  }

  List<Widget> _grouped(List<Reminder> list) {
    final overdue = list.where((r) => r.isOverdue).toList();
    final today = list.where((r) => r.isDueToday).toList();
    final upcoming =
        list.where((r) => !r.isOverdue && !r.isDueToday).toList();
    final widgets = <Widget>[];
    void section(String title, Color color, List<Reminder> items) {
      if (items.isEmpty) return;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            Text('${items.length}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ],
        ),
      ));
      for (final r in items) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ReminderCard(
            reminder: r,
            onToggleDone: () => _toggleDone(r),
            onEdit: () => _editReminder(r),
            onDelete: () => _deleteReminder(r),
          ),
        ));
      }
    }

    section('Overdue', Colors.redAccent, overdue);
    section('Due today', Colors.orangeAccent, today);
    section('Upcoming', Colors.blueAccent, upcoming);
    return widgets;
  }

  Future<void> _addReminder() async {
    final draft = await Navigator.of(context).push<ReminderDraft>(
      MaterialPageRoute(builder: (_) => const EditReminderScreen()),
    );
    if (draft == null) return;
    final r = Reminder(
      id: widget.storage.newId(),
      title: draft.title,
      category: draft.category,
      amount: draft.amount,
      dueDate: draft.dueDate,
      repeat: draft.repeat,
      remindBeforeDays: draft.remindBeforeDays,
      notes: draft.notes,
    );
    await widget.storage.save(r);
    await widget.notifications.schedule(r);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder added ✓')),
      );
    }
  }

  Future<void> _editReminder(Reminder r) async {
    final draft = await Navigator.of(context).push<ReminderDraft>(
      MaterialPageRoute(builder: (_) => EditReminderScreen(existing: r)),
    );
    if (draft == null) return;
    final updated = r.copyWith(
      title: draft.title,
      category: draft.category,
      amount: draft.amount,
      dueDate: draft.dueDate,
      repeat: draft.repeat,
      remindBeforeDays: draft.remindBeforeDays,
      notes: draft.notes,
    );
    await widget.storage.save(updated);
    await widget.notifications.cancel(r);
    await widget.notifications.schedule(updated);
  }

  Future<void> _toggleDone(Reminder r) async {
    if (r.done) return;
    final next = await widget.storage.markDone(r);
    await widget.notifications.cancel(r);
    if (next != null) await widget.notifications.schedule(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(next == null
                ? 'Marked done ✓'
                : 'Done ✓ — next due ${DateFormat('d MMM').format(next.dueDate)}')),
      );
    }
  }

  Future<void> _deleteReminder(Reminder r) async {
    await widget.notifications.cancel(r);
    await widget.storage.delete(r.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Reminder deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.storage.save(r);
            await widget.notifications.schedule(r);
          },
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HistoryScreen(
          storage: widget.storage,
          onRestore: (r) async {
            await widget.storage.save(r.copyWith(done: false));
            await widget.notifications.schedule(r.copyWith(done: false));
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final StorageService storage;
  const _SummaryCard({required this.storage});

  @override
  Widget build(BuildContext context) {
    final total = storage.totalDueThisMonth();
    final overdue = storage.overdueCount();
    final active = storage.active().length;
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFF4A3FD1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMMM y').format(now),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${_fmt(total)} due',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatChip(
                icon: Icons.warning_amber_rounded,
                label: '$overdue overdue',
                highlight: overdue > 0,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.upcoming_rounded,
                label: '$active active',
                highlight: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;
  const _StatChip(
      {required this.icon, required this.label, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.redAccent.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final ReminderCategory? selected;
  final ValueChanged<ReminderCategory?> onSelect;
  const _FilterRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelect(null),
          ),
          const SizedBox(width: 8),
          ...ReminderCategory.values.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.label),
                  selected: selected == c,
                  selectedColor: c.color.withValues(alpha: 0.2),
                  onSelected: (_) => onSelect(c),
                ),
              )),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('All clear! 🎉',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('No dues here. Add your first reminder.',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add reminder'),
          ),
        ],
      ),
    );
  }
}

/// Simple done-history list with restore.
class HistoryScreen extends StatelessWidget {
  final StorageService storage;
  final Future<void> Function(Reminder) onRestore;

  const HistoryScreen(
      {super.key, required this.storage, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ValueListenableBuilder(
        valueListenable: storage.listenable(),
        builder: (context, _, __) {
          final items = storage.history();
          if (items.isEmpty) {
            return const Center(child: Text('Nothing completed yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final r = items[i];
              return Card(
                child: ListTile(
                  leading: Icon(r.category.icon, color: r.category.color),
                  title: Text(r.title),
                  subtitle: Text(
                      '${r.category.label} • ${DateFormat('d MMM y').format(r.dueDate)}'),
                  trailing: r.amount != null
                      ? Text('₹${r.amount!.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold))
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
