import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';
import 'package:rail_automation/services/background_monitor.dart';
import 'package:rail_automation/services/foreground_monitor.dart';

class RecordingWorkmanager extends WorkmanagerPlatform {
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
    original = WorkmanagerPlatform.instance;
    platform = RecordingWorkmanager();
    WorkmanagerPlatform.instance = platform;
  });
  tearDown(() {
    WorkmanagerPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
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
