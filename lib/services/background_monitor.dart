import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'monitor_service.dart';
import 'notification_service.dart';
import 'pro_service.dart';
import 'foreground_monitor.dart';
import 'app_config.dart';
import 'app_update_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final pro = ProService();
    final monitor = MonitorService(proService: pro, backgroundWorker: true);
    try {
      await AppUpdateService.instance.refresh();
      await AppConfig.instance.reloadCache();
      await NotificationService().initialize(background: true);
      await monitor.restore(startTimers: false);
      if (!monitor.isMonitoring) {
        await BackgroundMonitor.cancel();
        return true;
      }
      // The native service owns fast polling while it is running. WorkManager
      // keeps the saved search alive between service sessions and after reboot.
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          await ForegroundMonitor.isRunning) {
        return true;
      }
      await monitor.checkNow();
      if (!monitor.isMonitoring) await BackgroundMonitor.cancel();
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await ForegroundMonitor.initialize();
    }
  }

  static Future<void> schedule({
    DateTime? startsAt,
    bool replaceSchedule = false,
  }) async {
    if (!supported) return;
    if (replaceSchedule) {
      await Workmanager().cancelByUniqueName(taskName);
    }
    final wait = startsAt?.difference(DateTime.now()) ?? Duration.zero;
    final delay = wait.isNegative ? Duration.zero : wait;
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(minutes: 15),
      // A single job handles both sales opening and recurring checks, avoiding
      // concurrent opening/fallback workers after a long network outage.
      initialDelay: delay > Duration.zero ? delay : const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (delay > Duration.zero) {
        await ForegroundMonitor.stop();
      } else {
        await ForegroundMonitor.start();
      }
    }
  }

  static Future<void> cancel() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await ForegroundMonitor.stop();
    }
    if (supported) {
      await Workmanager().cancelByUniqueName(taskName);
    }
  }
}
