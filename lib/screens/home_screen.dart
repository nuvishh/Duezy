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

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  ReminderCategory? _filter;
  final _searchController = TextEditingController();
  String _query = '';
  bool _bannerDismissed = false;
  // Keys of the permissions currently missing: 'notifications',
  // 'exactAlarms', 'battery'. Empty means reminders can alert on time.
  Set<String> _missing = {};

  static const _permissionLabels = {
    'notifications': 'Notifications',
    'exactAlarms': 'Exact alarms',
    'battery': 'Battery optimisation off',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings — re-check so the banner clears itself.
    if (state == AppLifecycleState.resumed) _checkPermissions();
  }

  /// Checks notifications + exact alarms + battery optimisation, and
  /// shows the alert again if the missing set changed since dismiss.
  Future<void> _checkPermissions() async {
    final missing = <String>{};
    if (!await widget.notifications.notificationsEnabled()) {
      missing.add('notifications');
    }
    if (!await widget.notifications.exactAlarmsEnabled()) {
      missing.add('exactAlarms');
    }
    if (!await widget.notifications.batteryOptimizationsIgnored()) {
      missing.add('battery');
    }
    if (!mounted) return;
    setState(() {
      if (missing.length != _missing.length ||
          !missing.containsAll(_missing)) {
        _bannerDismissed = false;
      }
      _missing = missing;
    });
  }

  /// Tries the in-app permission prompts for every missing item, then
  /// re-checks; anything still missing needs the Settings page.
  Future<void> _requestMissing() async {
    if (_missing.contains('notifications')) {
      await widget.notifications.requestNotifications();
    }
    if (_missing.contains('exactAlarms')) {
      await widget.notifications.requestExactAlarms();
    }
    if (_missing.contains('battery')) {
      await widget.notifications.requestBatteryExemption();
    }
    await _checkPermissions();
  }

  /// Permissions alert: status of all three, visible even when all are
  /// on, with Enable / Open Settings per item.
  Future<void> _showPermissionsDialog() async {
    final statuses = <String, bool>{
      'notifications':
          await widget.notifications.notificationsEnabled(),
      'exactAlarms': await widget.notifications.exactAlarmsEnabled(),
      'battery':
          await widget.notifications.batteryOptimizationsIgnored(),
    };
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refresh() async {
            final next = <String, bool>{
              'notifications': await widget.notifications
                  .notificationsEnabled(),
              'exactAlarms':
                  await widget.notifications.exactAlarmsEnabled(),
              'battery': await widget.notifications
                  .batteryOptimizationsIgnored(),
            };
            setDialogState(() => statuses.addAll(next));
            await _checkPermissions();
          }

          Future<void> enable(String key) async {
            if (key == 'notifications') {
              await widget.notifications.requestNotifications();
            } else if (key == 'exactAlarms') {
              await widget.notifications.requestExactAlarms();
            } else {
              await widget.notifications.requestBatteryExemption();
            }
            await refresh();
          }

          return AlertDialog(
            title: const Text('Permissions'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final key in _permissionLabels.keys)
                  _PermissionRow(
                    label: _permissionLabels[key]!,
                    enabled: statuses[key] ?? true,
                    onEnable: () => enable(key),
                    onOpenSettings: () async {
                      await widget.notifications.openSettings();
                      await refresh();
                    },
                  ),
                const SizedBox(height: 8),
                const Text(
                  'On MIUI, also turn on Autostart in Settings → Apps → Duezy.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⏰ Duezy'),
        actions: [
          IconButton(
            icon: Icon(
              _missing.isEmpty
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
            ),
            tooltip: 'Permissions',
            onPressed: _showPermissionsDialog,
          ),
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
          final q = _query.trim().toLowerCase();
          final searched = q.isEmpty
              ? all
              : all
                  .where((r) =>
                      r.title.toLowerCase().contains(q) ||
                      (r.notes ?? '').toLowerCase().contains(q) ||
                      r.category.label.toLowerCase().contains(q))
                  .toList();
          final list = _filter == null
              ? searched
              : searched.where((r) => r.category == _filter).toList();
          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCard(storage: widget.storage),
                if (_missing.isNotEmpty && !_bannerDismissed) ...[
                  const SizedBox(height: 12),
                  _PermissionsBanner(
                    missingLabels: _missing
                        .map((k) => _permissionLabels[k]!)
                        .toList(),
                    onAllow: _requestMissing,
                    onOpenSettings: () =>
                        widget.notifications.openSettings(),
                    onDismiss: () =>
                        setState(() => _bannerDismissed = true),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search reminders…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _FilterRow(
                  selected: _filter,
                  onSelect: (c) => setState(() => _filter = c),
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  _query.trim().isEmpty
                      ? _EmptyState(onAdd: _addReminder)
                      : _NoResults(
                          query: _query.trim(),
                          onClear: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
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
      remindAt: draft.remindAt,
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
      remindAt: draft.remindAt,
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
    final scheme = Theme.of(context).colorScheme;
    final onPrimary = scheme.onPrimary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMMM y').format(now),
            style: TextStyle(color: onPrimary.withValues(alpha: 0.75), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${_fmt(total)} due',
            style: TextStyle(
              color: onPrimary,
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

/// Shown when any reminder permission is missing: reminders are
/// scheduled but may not alert on time. "Allow" tries the in-app
/// prompts; "Settings" opens the system App info page for Duezy.
class _PermissionsBanner extends StatelessWidget {
  final List<String> missingLabels;
  final VoidCallback onAllow;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  const _PermissionsBanner({
    required this.missingLabels,
    required this.onAllow,
    required this.onOpenSettings,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_off_rounded,
                  color: Colors.orangeAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Missing: ${missingLabels.join(' • ')} — reminders may not alert on time.',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Dismiss',
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: onAllow,
                child: const Text('Allow'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of the Permissions dialog: status + Enable / Settings.
class _PermissionRow extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onEnable;
  final VoidCallback onOpenSettings;

  const _PermissionRow({
    required this.label,
    required this.enabled,
    required this.onEnable,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            enabled
                ? Icons.check_circle_rounded
                : Icons.error_rounded,
            color: enabled ? Colors.green : Colors.orangeAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (!enabled) ...[
            TextButton(onPressed: onEnable, child: const Text('Enable')),
            TextButton(
                onPressed: onOpenSettings, child: const Text('Settings')),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;
  const _StatChip(
      {required this.icon, required this.label, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.redAccent.withValues(alpha: 0.9)
            : onPrimary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: onPrimary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: onPrimary, fontSize: 12)),
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

class _NoResults extends StatelessWidget {
  final String query;
  final VoidCallback onClear;
  const _NoResults({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No matches',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Nothing matches "$query".',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded),
            label: const Text('Clear search'),
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
