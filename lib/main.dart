import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workmanager/workmanager.dart';

import 'safety_net_task.dart';
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
  // Safety net (Android only): MIUI/HyperOS swallows even setAlarmClock
  // alarms on some devices (verified on the user's Redmi 12 5G,
  // 2026-11-13). A periodic worker re-checks every 15 minutes and
  // shows any due reminder directly — the alarm path stays primary.
  // Best effort: if registration fails, the alarm path still works.
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Workmanager().initialize(safetyNetCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        'duezy-safety-net',
        'duezy-safety-net-check',
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // Registration failed (e.g. background work unavailable) — the
      // alarm path remains, and the next launch retries registration.
    }
  }
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

  ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Material You: follow the device wallpaper colors on Android 12+,
    // fall back to the Duezy seed purple everywhere else.
    const seed = Color(0xFF6C5CE7);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme = lightDynamic ??
            ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.light,
            );
        final darkScheme = darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: seed,
              brightness: Brightness.dark,
            );

        return MaterialApp(
          title: 'Duezy',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(lightScheme),
          darkTheme: _buildTheme(darkScheme),
          home: HomeScreen(storage: storage, notifications: notifications),
        );
      },
    );
  }
}
