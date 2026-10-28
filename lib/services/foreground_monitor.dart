import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_config.dart';
import 'booking_activity.dart';
import 'booking_service.dart';
import 'app_update_service.dart';
import 'firebase_user_service.dart';
import 'monitor_service.dart';
import 'notification_service.dart';
import 'pro_service.dart';
import 'otp_verifier.dart';
import 'overlay_service.dart';
import 'sms_service.dart';
import 'turnstile_gate.dart';
import 'turnstile_session.dart';

@pragma('vm:entry-point')
void monitoringEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  final pro = ProService();
  final monitor = MonitorService(proService: pro, backgroundWorker: true);
  Timer? timer;
  Timer? sessionTimer;
  bool stopped = false;
  bool busy = false;
  void reportActivity() {
    final activity = BookingActivity.instance;
    service.invoke('booking-activity', {
      'stage': activity.busy ? activity.stage.name : null,
    });
  }

  BookingActivity.instance.addListener(reportActivity);
  service.on('booking-activity-request').listen((_) => reportActivity());
  // A service isolate cannot own a visible platform view. Reuse the rendered
  // browser in the UI engine via service messages, including while it is idle.
  TurnstileGate.instance.workerAcquire = (label) async {
    final result = await ForegroundMonitor.requestVerificationToken(
      service,
      label,
    );
    TurnstileGate.instance.workerPromptPresented = result.$2;
    if (result.$1 == null && !result.$2) {
      // The app may have closed after this monitoring cycle checked visibility.
      NotificationService().appVisible = false;
    }
    return result.$1;
  };
  service.on('stop').listen((_) async {
    if (stopped) return;
    stopped = true;
    timer?.cancel();
    sessionTimer?.cancel();
    BookingActivity.instance.removeListener(reportActivity);
    service.invoke('booking-activity', {'stage': null});
    SmsService().stopListening();
    monitor.dispose();
    pro.dispose();
    await service.stopSelf();
  });
  await FirebaseUserService().initialize();
  await AppConfig.instance.initialize();
  await NotificationService().initialize(background: true);
  // Android limits data-sync service runtime. This limits only fast polling;
  // durable WorkManager checks continue until departure without reopening UI.
  sessionTimer = Timer(const Duration(hours: 5), () async {
    stopped = true;
    timer?.cancel();
    BookingActivity.instance.removeListener(reportActivity);
    service.invoke('booking-activity', {'stage': null});
    SmsService().stopListening();
    await NotificationService().showBackgroundSearchContinues();
    monitor.dispose();
    pro.dispose();
    await service.stopSelf();
  });
  Future<void> tick() async {
    if (busy || stopped) return;
    busy = true;
    try {
      await AppUpdateService.instance.refresh();
      final visibility = Completer<bool>();
      final visibilityId = DateTime.now().microsecondsSinceEpoch.toString();
      final visibilitySub = service.on('ui-visibility-result').listen((event) {
        if (event?['id'] == visibilityId && !visibility.isCompleted) {
          visibility.complete(event?['visible'] == true);
        }
      });
      try {
        service.invoke('ui-visibility-request', {'id': visibilityId});
        NotificationService().appVisible = await visibility.future.timeout(
          const Duration(milliseconds: 250),
          onTimeout: () => false,
        );
      } finally {
        await visibilitySub.cancel();
      }
      await monitor.restore(startTimers: false);
      if (!monitor.isMonitoring || monitor.isScheduled) {
        stopped = true;
        timer?.cancel();
        sessionTimer?.cancel();
        BookingActivity.instance.removeListener(reportActivity);
        service.invoke('booking-activity', {'stage': null});
        monitor.dispose();
        pro.dispose();
        await service.stopSelf();
        return;
      }
      await monitor.checkNow();
      BookingActivity.instance.setWorkerStage(null);
      service.invoke('booking-activity', {'stage': null});
      if (!monitor.isMonitoring && await BookingService.pending() == null) {
        stopped = true;
        sessionTimer?.cancel();
        BookingActivity.instance.removeListener(reportActivity);
        SmsService().stopListening();
        monitor.dispose();
        pro.dispose();
        await service.stopSelf();
        return;
      }
      await OtpVerifier.listen();
      if (stopped) return;
      if (service is AndroidServiceInstance) {
        final bn = await NotificationService.prefersBangla();
        await service.setForegroundNotificationInfo(
          title: '${monitor.fromCity} → ${monitor.toCity}',
          content: monitor.lastError == null
              ? (bn
                    ? 'আসন খোঁজা হচ্ছে · ${monitor.dateOfJourney}'
                    : 'Finding seats · ${monitor.dateOfJourney}')
              : monitor.userStatus,
        );
      }
      service.invoke('updated');
    } finally {
      busy = false;
      if (!stopped) {
        timer = Timer(monitor.nextCheckDelay(), tick);
      }
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
  static int _verificationSequence = 0;

  static Future<(String?, bool)> requestVerificationToken(
    ServiceInstance service,
    String label, {
    Duration ackTimeout = const Duration(milliseconds: 750),
    Duration responseTimeout = const Duration(seconds: 120),
  }) async {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${++_verificationSequence}';
    final response = Completer<Map<String, dynamic>?>();
    final acknowledged = Completer<void>();
    var presented = false;
    final ackSubscription = service.on('verification-ack').listen((event) {
      if (event?['id'] == id && !acknowledged.isCompleted) {
        presented = event?['presented'] == true;
        acknowledged.complete();
      }
    });
    final subscription = service.on('verification-result').listen((event) {
      if (event?['id'] == id && !response.isCompleted) response.complete(event);
    });
    try {
      service.invoke('verification-request', {'id': id, 'label': label});
      // A destroyed UI engine cannot answer. Leave a pending notification
      // promptly instead of stalling the booking worker for two minutes.
      try {
        await acknowledged.future.timeout(ackTimeout);
      } on TimeoutException {
        return (null, false);
      }
      final result = await response.future.timeout(
        responseTimeout,
        onTimeout: () => null,
      );
      return (
        result?['token'] as String?,
        result?['presented'] as bool? ?? presented,
      );
    } finally {
      await subscription.cancel();
      await ackSubscription.cancel();
      service.invoke('verification-cancel', {'id': id});
    }
  }

  static StreamSubscription<Map<String, dynamic>?>? _verificationRequests;
  static StreamSubscription<Map<String, dynamic>?>? _verificationCancellations;
  static String? _activeVerificationId;
  static StreamSubscription<Map<String, dynamic>?>? _visibilityRequests;
  static StreamSubscription<Map<String, dynamic>?>? _bookingActivity;

  /// Install before starting the service. The browser is preloaded by the
  /// MaterialApp host and survives navigation and app backgrounding in memory.
  static void connectVerificationUi() {
    _bookingActivity ??= FlutterBackgroundService()
        .on('booking-activity')
        .listen((event) {
          final name = event?['stage'];
          BookingActivity.instance.setWorkerStage(
            BookingActivityStage.values
                .where((stage) => stage.name == name)
                .firstOrNull,
          );
        });
    FlutterBackgroundService().invoke('booking-activity-request');
    _visibilityRequests ??= FlutterBackgroundService()
        .on('ui-visibility-request')
        .listen((event) {
          FlutterBackgroundService().invoke('ui-visibility-result', {
            'id': event?['id'],
            'visible': TurnstileGate.instance.canShowUi,
          });
        });
    _verificationRequests ??= FlutterBackgroundService()
        .on('verification-request')
        .listen((event) async {
          final id = event?['id'] as String?;
          if (id == null) return;
          final gate = TurnstileGate.instance;
          final foreground = gate.canShowUi;
          FlutterBackgroundService().invoke('verification-ack', {
            'id': id,
            'presented': foreground,
          });
          final blocked =
              _activeVerificationId != null ||
              gate.isShowing ||
              TurnstileSession.instance.generating;
          final canOverlay =
              OverlayService.isAndroid &&
              !foreground &&
              await OverlayService.canDrawOverlays();
          if (blocked || (!gate.canRunSilently && !canOverlay)) {
            FlutterBackgroundService().invoke('verification-result', {
              'id': id,
              'presented':
                  foreground &&
                  (gate.isShowing || TurnstileSession.instance.generating),
            });
            return;
          }
          _activeVerificationId = id;
          try {
            String? token;
            // 1) Silent solve. Foreground may show the in-app overlay; the
            //    background gets one short silent try only.
            if (gate.canRunSilently) {
              token = await gate
                  .acquire(
                    label: event?['label'] as String? ?? '',
                    forceFresh: true,
                    allowPrompt: foreground,
                  )
                  .timeout(
                    foreground
                        ? const Duration(seconds: 110)
                        : const Duration(seconds: 20),
                    onTimeout: () {
                      TurnstileSession.instance.cancel();
                      return null;
                    },
                  );
            }
            // 2) Minimized and the silent try failed: a small visible card over
            //    other apps. One tap, no need to open Rail Pro.
            if ((token == null || token.isEmpty) &&
                canOverlay &&
                _activeVerificationId == id) {
              final bn = await NotificationService.prefersBangla();
              token = await OverlayService.solveVerification(
                siteKey: gate.seatLayoutSiteKey,
                title: bn
                    ? 'টিকেট বুক করতে যাচাই করুন'
                    : 'Verify to book your ticket',
                message: bn
                    ? 'সিট পাওয়া গেছে। একবার যাচাই করুন।'
                    : 'Seats found. Complete the check to continue.',
              );
            }
            if (_activeVerificationId == id) {
              FlutterBackgroundService().invoke('verification-result', {
                'id': id,
                'token': token,
                'presented': foreground,
              });
            }
          } finally {
            if (_activeVerificationId == id) _activeVerificationId = null;
          }
        });
    _verificationCancellations ??= FlutterBackgroundService()
        .on('verification-cancel')
        .listen((event) {
          if (event?['id'] == _activeVerificationId) {
            _activeVerificationId = null;
            TurnstileSession.instance.cancel();
            TurnstileGate.instance.dismiss();
            unawaited(OverlayService.hideVerification());
          }
        });
  }

  static Future<void> disconnectVerificationUi() async {
    await _bookingActivity?.cancel();
    _bookingActivity = null;
    BookingActivity.instance.setWorkerStage(null);
    await _visibilityRequests?.cancel();
    _visibilityRequests = null;
    await _verificationRequests?.cancel();
    await _verificationCancellations?.cancel();
    _verificationRequests = null;
    _verificationCancellations = null;
    _activeVerificationId = null;
    TurnstileSession.instance.cancel();
  }

  static Future<void> syncBookingActivity() async {
    if (!initialized) return;
    if (await FlutterBackgroundService().isRunning()) {
      FlutterBackgroundService().invoke('booking-activity-request');
    } else {
      BookingActivity.instance.setWorkerStage(null);
    }
  }

  static Stream<Map<String, dynamic>?> get updates =>
      FlutterBackgroundService().on('updated');
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
    final bn = await NotificationService.prefersBangla();
    await FlutterBackgroundService().configure(
      iosConfiguration: IosConfiguration(autoStart: false),
      androidConfiguration: AndroidConfiguration(
        onStart: monitoringEntryPoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: 'rail_monitor',
        initialNotificationTitle: 'Rail Pro',
        initialNotificationContent: bn
            ? 'অনুসন্ধান শুরু হচ্ছে…'
            : 'Starting your search…',
        foregroundServiceNotificationId: 771,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
    );
    initialized = true;
  }

  // WorkManager has its own isolate, where initialized is false even when the
  // native foreground service is running. Query Android rather than that flag.
  static Future<bool> get isRunning => FlutterBackgroundService().isRunning();

  static Future<void> start() async {
    if (!initialized) {
      throw StateError('Background monitoring is not initialized');
    }
    if (await FlutterBackgroundService().isRunning()) {
      FlutterBackgroundService().invoke('refresh');
    } else if (!await FlutterBackgroundService().startService()) {
      throw StateError('Unable to start background monitoring');
    }
  }

  static Future<void> stop() async {
    if (!initialized) return;
    TurnstileGate.instance.dismiss();
    FlutterBackgroundService().invoke('stop');
    BookingActivity.instance.setWorkerStage(null);
    for (var i = 0; i < 30; i++) {
      if (!await FlutterBackgroundService().isRunning()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Monitoring is still stopping. Please try again.');
  }
}
