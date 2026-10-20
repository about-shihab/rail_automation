import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:workmanager/workmanager.dart';
// ignore: depend_on_referenced_packages
import 'package:workmanager_android/workmanager_android.dart';
import 'package:rail_automation/services/background_monitor.dart';
import 'package:rail_automation/services/foreground_monitor.dart';

class RecordingWorkmanager extends WorkmanagerAndroid {
  final cancelled = <String>[];
  final oneOffDelays = <Duration?>[];
  final periodicDelays = <Duration?>[];
  final periodicPolicies = <ExistingPeriodicWorkPolicy?>[];
  var initializations = 0;

  @override
  Future<void> initialize(
    Function callbackDispatcher, {
    bool isInDebugMode = false,
  }) async {
    initializations++;
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled.add(uniqueName);
  }

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    oneOffDelays.add(initialDelay);
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    expect(frequency, const Duration(minutes: 15));
    expect(constraints?.networkType, NetworkType.connected);
    periodicDelays.add(initialDelay);
    periodicPolicies.add(existingWorkPolicy);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingWorkmanager platform;
  late WorkmanagerPlatform original;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    Workmanager();
    original = WorkmanagerPlatform.instance;
    platform = RecordingWorkmanager();
    WorkmanagerPlatform.instance = platform;
    ForegroundMonitor.initialized = false;
  });
  tearDown(() {
    WorkmanagerPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    ForegroundMonitor.initialized = false;
  });

  test('future Android search uses a single delayed recurring job', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await BackgroundMonitor.schedule(
      startsAt: DateTime.now().add(const Duration(days: 3)),
      replaceSchedule: true,
    );
    expect(platform.cancelled, [BackgroundMonitor.taskName]);
    expect(
      platform.periodicDelays.single!.inSeconds,
      closeTo(const Duration(days: 3).inSeconds, 600),
    );
    expect(platform.oneOffDelays, isEmpty);
    expect(platform.periodicPolicies.single, ExistingPeriodicWorkPolicy.keep);
    await BackgroundMonitor.cancel();
    expect(platform.cancelled.length, 2);
  });

  test('initialization and restoration preserve queued work', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await BackgroundMonitor.initialize();
    expect(platform.initializations, 1);
    expect(platform.cancelled, isEmpty);
    await BackgroundMonitor.schedule();
    expect(platform.cancelled, isEmpty);
    expect(platform.periodicDelays.single, const Duration(minutes: 15));
    expect(platform.oneOffDelays, isEmpty);
    expect(platform.periodicPolicies.single, ExistingPeriodicWorkPolicy.keep);
  });

  test(
    'iOS keeps a pending native refresh instead of postponing it on resume',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const channel = MethodChannel('com.example.rail_automation/overlay');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'isSearchBackgroundScheduled');
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await BackgroundMonitor.schedule();
      await BackgroundMonitor.schedule();
      expect(platform.periodicDelays, isEmpty);
      await BackgroundMonitor.schedule(replaceSchedule: true);
      expect(platform.cancelled, [BackgroundMonitor.taskName]);
      expect(platform.periodicDelays, hasLength(1));
    },
  );

  test('iOS restores an active search status and reports disabled notification permission', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    const notifications = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    final calls = <MethodCall>[];
    var allowed = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'checkPermissions') return {'isEnabled': allowed};
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notifications, null),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      MonitorService.preferenceKey,
      jsonEncode({
        'id': 'restored-ios',
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': DateFormat('dd-MMM-yyyy')
            .format(DateTime.now().add(const Duration(days: 20))),
        'active': true,
        'expires': DateTime.now()
            .add(const Duration(days: 21))
            .toIso8601String(),
      }),
    );
    final pro = ProService();
    final monitor = MonitorService(proService: pro);
    addTearDown(monitor.dispose);
    addTearDown(pro.dispose);
    await monitor.restore();
    expect(platform.periodicDelays, hasLength(1));
    expect(
      calls.where((c) => c.method == 'show').single.arguments['id'],
      NotificationService.idIosSearchStatus,
    );
    allowed = false;
    await monitor.restore();
    expect(monitor.backgroundError, contains('iPhone Settings'));
    expect(monitor.userStatus, contains('iPhone Settings'));
  });

  test(
    'worker checks native service status even before isolate initialization',
    () async {
      const channel = MethodChannel(
        'id.flutter/background_service/android/method',
        JSONMethodCodec(),
      );
      FlutterBackgroundServiceAndroid.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => true);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(ForegroundMonitor.initialized, isFalse);
      expect(await ForegroundMonitor.isRunning, isTrue);
    },
  );
}
