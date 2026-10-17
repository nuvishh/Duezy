import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reminder.dart';

/// Add / edit form for a reminder.
class EditReminderScreen extends StatefulWidget {
  final Reminder? existing;

  const EditReminderScreen({super.key, this.existing});

  @override
  State<EditReminderScreen> createState() => _EditReminderScreenState();
}

class _EditReminderScreenState extends State<EditReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late ReminderCategory _category;
  late DateTime _dueDate;
  late RepeatInterval _repeat;
  late int _remindBefore;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _amount = TextEditingController(
        text: e?.amount != null ? _fmtNum(e!.amount!) : '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? ReminderCategory.subscription;
    _dueDate = e?.dueDate ?? DateTime.now().add(const Duration(days: 1));
    _repeat = e?.repeat ?? RepeatInterval.none;
    _remindBefore = e?.remindBeforeDays ?? 1;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit reminder' : 'New reminder')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Netflix, Home loan EMI, Bike insurance',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Give it a title' : null,
            ),
            const SizedBox(height: 16),
            const Text('Category',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReminderCategory.values.map((c) {
                final selected = c == _category;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(c.icon, size: 16),
                      const SizedBox(width: 6),
                      Text(c.label),
                    ],
                  ),
                  selected: selected,
                  selectedColor: c.color.withValues(alpha: 0.2),
                  onSelected: (_) => setState(() => _category = c),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount (₹, optional)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      return double.tryParse(v.trim()) == null
                          ? 'Enter a number'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Due date',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(DateFormat('d MMM y').format(_dueDate)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<RepeatInterval>(
                    initialValue: _repeat,
                    decoration: const InputDecoration(
                      labelText: 'Repeats',
                      border: OutlineInputBorder(),
                    ),
                    items: RepeatInterval.values
                        .map((r) => DropdownMenuItem(
                            value: r, child: Text(r.label)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _repeat = v ?? RepeatInterval.none),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _remindBefore,
                    decoration: const InputDecoration(
                      labelText: 'Remind me',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('On the day')),
                      DropdownMenuItem(value: 1, child: Text('1 day before')),
                      DropdownMenuItem(value: 3, child: Text('3 days before')),
                      DropdownMenuItem(value: 7, child: Text('1 week before')),
                    ],
                    onChanged: (v) =>
                        setState(() => _remindBefore = v ?? 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Policy number, account, etc.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(isEdit ? 'Save changes' : 'Add reminder'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(ReminderDraft(
      title: _title.text.trim(),
      category: _category,
      amount: _amount.text.trim().isEmpty
          ? null
          : double.parse(_amount.text.trim()),
      dueDate: _dueDate,
      repeat: _repeat,
      remindBeforeDays: _remindBefore,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    ));
  }

  String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}

/// Form result handed back to the home screen, which owns storage.
class ReminderDraft {
  final String title;
  final ReminderCategory category;
  final double? amount;
  final DateTime dueDate;
  final RepeatInterval repeat;
  final int remindBeforeDays;
  final String? notes;

  ReminderDraft({
    required this.title,
    required this.category,
    this.amount,
    required this.dueDate,
    required this.repeat,
    required this.remindBeforeDays,
    this.notes,
  });
}

