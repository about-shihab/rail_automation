import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_config.dart';
import 'firebase_user_service.dart';
import 'monitor_service.dart';
import 'notification_service.dart';
import 'pro_service.dart';
import 'otp_verifier.dart';
import 'sms_service.dart';

@pragma('vm:entry-point')
void monitoringEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  final pro = ProService();
  final monitor = MonitorService(proService: pro, backgroundWorker: true);
  Timer? timer;
  bool stopped = false;
  bool busy = false;
  service.on('stop').listen((_) async {
    stopped = true;
    timer?.cancel();
    SmsService().stopListening();
    monitor.dispose();
    pro.dispose();
    await service.stopSelf();
  });
  // User-visible sessions are bounded below Android's data-sync quota.
  Timer(const Duration(hours: 5), () async {
    stopped = true;
    timer?.cancel();
    SmsService().stopListening();
    monitor.stopMonitoring();
    await service.stopSelf();
  });
  await FirebaseUserService().initialize();
  await AppConfig.instance.initialize();
  await NotificationService().initialize(background: true);
  Future<void> tick() async {
    if (busy || stopped) return;
    busy = true;
    try {
      await monitor.restore(startTimers: false);
      if (!monitor.isMonitoring) {
        stopped = true;
        timer?.cancel();
        await service.stopSelf();
        return;
      }
      await monitor.checkNow();
      await OtpVerifier.listen();
      if (stopped) return;
      if (service is AndroidServiceInstance) {
        await service.setForegroundNotificationInfo(
          title: '${monitor.fromCity} → ${monitor.toCity}',
          content: monitor.lastError == null
              ? 'Watching for your seats • Tap to view your journey'
              : monitor.userStatus,
        );
      }
      service.invoke('updated');
    } finally {
      busy = false;
      if (!stopped)
        timer = Timer(Duration(seconds: AppConfig.instance.pollSeconds), tick);
    }
  }

  service.on('refresh').listen((_) {
    timer?.cancel();
    tick();
  });
  await tick();
}

class ForegroundMonitor {
  static bool initialized = false;
  static Future<void> initialize() async {
    const channel = AndroidNotificationChannel(
      'rail_monitor',
      'Active ticket monitoring',
      importance: Importance.low,
    );
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    await FlutterBackgroundService().configure(
      iosConfiguration: IosConfiguration(autoStart: false),
      androidConfiguration: AndroidConfiguration(
        onStart: monitoringEntryPoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: 'rail_monitor',
        initialNotificationTitle: 'Ticket monitoring',
        initialNotificationContent: 'Starting your saved search',
        foregroundServiceNotificationId: 771,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
    );
    initialized = true;
  }

  static Future<void> start() async {
    if (!initialized)
      throw StateError('Background monitoring is not initialized');
    if (await FlutterBackgroundService().isRunning()) {
      FlutterBackgroundService().invoke('refresh');
    } else if (!await FlutterBackgroundService().startService()) {
      throw StateError('Unable to start background monitoring');
    }
  }

  static Future<void> stop() async {
    if (!initialized) return;
    FlutterBackgroundService().invoke('stop');
    for (var i = 0; i < 30; i++) {
      if (!await FlutterBackgroundService().isRunning()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Monitoring is still stopping. Please try again.');
  }
}
