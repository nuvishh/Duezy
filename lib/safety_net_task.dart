import 'package:workmanager/workmanager.dart';

import 'services/notification_service.dart';
import 'services/safety_net.dart';
import 'services/storage_service.dart';

/// Background entry point for the WorkManager safety net. Must stay a
/// top-level function and be kept by tree-shaking.
@pragma('vm:entry-point')
void safetyNetCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final storage = StorageService();
      await storage.init();
      final notifications = NotificationService();
      await notifications.initHeadless();
      await SafetyNetService(
        storage: storage,
        notifications: notifications,
      ).checkAndNotify();
    } catch (_) {
      // A failed run must not crash the worker: the next 15-minute run
      // retries (e.g. the Hive box was briefly held by the main
      // isolate when the worker started).
    }
    return true;
  });
}
