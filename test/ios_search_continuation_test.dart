import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/services/ios_search_continuation.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';

class _Monitor extends MonitorService {
  _Monitor() : super(proService: ProService());
  bool active = true;
  int checks = 0;
  final check = Completer<void>();
  @override
  bool get isMonitoring => active;
  @override
  Future<void> checkNow() {
    checks++;
    return check.future;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.rail_automation/overlay');
  final calls = <MethodCall>[];
  int? granted;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    granted = 42;
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'beginSearchBackgroundTask' ? granted : null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'one background lease covers the search and is released exactly once',
    () async {
      final monitor = _Monitor();
      final result = IosSearchContinuation.run(monitor);
      await Future<void>.delayed(Duration.zero);
      expect(monitor.checks, 1);
      await IosSearchContinuation.run(monitor);
      expect(monitor.checks, 1);
      monitor.check.complete();
      await result;
      expect(calls.map((c) => c.method), [
        'beginSearchBackgroundTask',
        'endSearchBackgroundTask',
      ]);
      expect(calls.last.arguments, {'id': 42});
      monitor.dispose();
      monitor.proService.dispose();
    },
  );
  test(
    'denied runtime does not start another unprotected network search',
    () async {
      granted = null;
      final monitor = _Monitor();
      await IosSearchContinuation.run(monitor);
      expect(monitor.checks, 0);
      expect(calls, hasLength(1));
      monitor.dispose();
      monitor.proService.dispose();
    },
  );
  test('failure still releases the lease', () async {
    final monitor = _Monitor();
    final result = IosSearchContinuation.run(monitor);
    await Future<void>.delayed(Duration.zero);
    monitor.check.completeError(StateError('offline'));
    await result;
    expect(calls.last.method, 'endSearchBackgroundTask');
    monitor.dispose();
    monitor.proService.dispose();
  });
  test('Android does not invoke iOS continuation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final monitor = _Monitor();
    await IosSearchContinuation.run(monitor);
    expect(calls, isEmpty);
    monitor.dispose();
    monitor.proService.dispose();
  });
}
