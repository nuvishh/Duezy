import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();
  final notifications = NotificationService();
  await notifications.init();
  // Schedule everything on every launch (cheap, idempotent).
  await notifications.rescheduleAll(storage.active());
  runApp(DuezyApp(storage: storage, notifications: notifications));
}

class DuezyApp extends StatelessWidget {
  final StorageService storage;
  final NotificationService notifications;

  const DuezyApp({
    super.key,
    required this.storage,
    required this.notifications,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Duezy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(storage: storage, notifications: notifications),
    );
  }
}
