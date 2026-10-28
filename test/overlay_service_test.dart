import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rail_automation/services/overlay_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.rail_automation/overlay');
  final log = <MethodCall>[];
  bool canDraw = true;
  String? solveToken = 'sample-token';

  setUp(() {
    log.clear();
    canDraw = true;
    solveToken = 'sample-token';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'canDrawOverlays':
          return canDraw;
        case 'requestOverlayPermission':
          return canDraw;
        case 'showVerification':
          return solveToken;
        case 'hideVerification':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('canDrawOverlays queries the overlay channel on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await OverlayService.canDrawOverlays(), isTrue);
    expect(log.last.method, 'canDrawOverlays');

    canDraw = false;
    expect(await OverlayService.canDrawOverlays(), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  test('requestPermission invokes requestOverlayPermission on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    canDraw = false;
    expect(await OverlayService.requestPermission(), isFalse);
    expect(log.last.method, 'requestOverlayPermission');

    canDraw = true;
    expect(await OverlayService.requestPermission(), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  test('solveVerification requests overlay token and passes arguments', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    canDraw = true;
    solveToken = 'solved-123';

    final result = await OverlayService.solveVerification(
      siteKey: '0x4AAAAAA',
      title: 'Test Verification',
      message: 'Solve to continue',
    );

    expect(result, 'solved-123');
    final showCall = log.firstWhere((c) => c.method == 'showVerification');
    expect(showCall.arguments['siteKey'], '0x4AAAAAA');
    expect(showCall.arguments['title'], 'Test Verification');
    expect(showCall.arguments['message'], 'Solve to continue');
    debugDefaultTargetPlatformOverride = null;
  });

  test('solveVerification returns null if overlay permission is not granted', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    canDraw = false;

    final result = await OverlayService.solveVerification(
      siteKey: '0x4AAAAAA',
      title: 'Test Verification',
      message: 'Solve to continue',
    );

    expect(result, isNull);
    expect(log.any((c) => c.method == 'showVerification'), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  test('hideVerification invokes hideVerification on channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await OverlayService.hideVerification();
    expect(log.last.method, 'hideVerification');
    debugDefaultTargetPlatformOverride = null;
  });
}

