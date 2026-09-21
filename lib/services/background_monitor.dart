import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'monitor_service.dart';
import 'notification_service.dart';
import 'pro_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final pro = ProService();
    final monitor = MonitorService(proService: pro);
    try {
      await NotificationService().initialize(background: true);
      await monitor.restore(startTimers: false);
      if (!monitor.isMonitoring) {
        await BackgroundMonitor.cancel();
        return true;
      }
      await monitor.checkNow();
      return monitor.lastError == null;
    } finally {
      monitor.dispose();
      pro.dispose();
    }
  });
}

class BackgroundMonitor {
  static const taskName = 'com.example.rail_automation.ticketSearch';
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() async {
    if (supported) await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> schedule() async {
    if (!supported) return;
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> cancel() async {
    if (supported) await Workmanager().cancelByUniqueName(taskName);
  }
}
