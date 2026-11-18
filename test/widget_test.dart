import 'package:duezy/models/reminder.dart';
import 'package:duezy/widgets/reminder_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('ReminderCard smoke test', (WidgetTester tester) async {
    final reminder = Reminder(
      id: 'test-1',
      title: 'Netflix Subscription',
      category: ReminderCategory.subscription,
      amount: 499,
      dueDate: DateTime.now().add(const Duration(days: 3)),
      repeat: RepeatInterval.monthly,
      remindBeforeDays: 1,
      remindAt: const TimeOfDay(hour: 9, minute: 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReminderCard(
            reminder: reminder,
            onToggleDone: () {},
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('Netflix Subscription'), findsOneWidget);
    expect(find.text('₹499'), findsOneWidget);
  });
}
