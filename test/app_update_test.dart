import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/services/app_update_service.dart';
import 'package:rail_automation/widgets/app_update_gate.dart';

Map<String, dynamic> manifest({int build = 4, int minimum = 3}) => {
  'version': '1.0.3',
  'build_number': build,
  'minimum_build_number': minimum,
  'apk_url': 'https://rail.example/downloads/Rail-Pro.apk',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      AppUpdateService.installedKey: 2,
      AppUpdateService.versionKey: '1.0.1',
    });
  });

  test(
    'minimum build distinguishes mandatory, optional and current releases',
    () {
      final policy = UpdatePolicy.parse(manifest())!;
      expect(policy.requiresUpdate(2), isTrue);
      expect(policy.requiresUpdate(3), isFalse);
      expect(policy.requiresUpdate(4), isFalse);
      expect(policy.requiresUpdate(5), isFalse);
      expect(policy.requiresUpdate(0), isFalse);
    },
  );

  test('invalid policy cannot lock users to an unavailable release', () {
    for (final value in [
      {...manifest(), 'minimum_build_number': 5},
      {...manifest(), 'build_number': '4'},
      {...manifest(), 'minimum_build_number': -1},
      {...manifest(), 'version': 'latest'},
      {...manifest(), 'apk_url': 'http://rail.example/app.apk'},
      {...manifest(), 'apk_url': 'https://secret@rail.example/app.apk'},
      {...manifest(), 'apk_url': 'https://github.com/private/repo/releases'},
      {...manifest(), 'apk_url': 'javascript:alert(1)'},
    ]) {
      expect(UpdatePolicy.parse(value), isNull);
    }
  });

  test(
    'native installed version replaces a stale cached build after installation',
    () async {
      const channel = MethodChannel('com.example.rail_automation/overlay');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {'version': '1.0.3', 'build': 4},
          );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppUpdateService.cacheKey, jsonEncode(manifest()));
      final updates = AppUpdateService();
      await updates.initialize();
      expect(updates.installedVersion, '1.0.3');
      expect(updates.installedBuild, 4);
      expect(updates.required, isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  test(
    'concurrent and repeated checks use one request and cache mandatory policy',
    () async {
      var requests = 0;
      final updates = AppUpdateService(
        client: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(manifest()), 200);
        }),
      );
      await Future.wait([updates.refresh(), updates.refresh()]);
      await updates.refresh();
      expect(requests, 1);
      expect(updates.required, isTrue);
      await expectLater(updates.ensureBookingAllowed(), throwsStateError);
      final worker = AppUpdateService();
      await worker.reloadCache();
      expect(worker.required, isTrue);
    },
  );

  test(
    'offline and malformed responses retain a known mandatory update',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppUpdateService.cacheKey, jsonEncode(manifest()));
      for (final response in [
        http.Response('', 503),
        http.Response('{}', 200),
      ]) {
        final updates = AppUpdateService(
          client: MockClient((_) async => response),
        );
        await updates.refresh();
        expect(updates.required, isTrue);
        expect(updates.error, isNotNull);
      }
    },
  );

  test(
    'first offline launch remains usable without a valid mandatory policy',
    () async {
      final updates = AppUpdateService(
        client: MockClient((_) async => http.Response('', 404)),
      );
      await updates.refresh();
      expect(updates.required, isFalse);
      await updates.ensureBookingAllowed();
    },
  );

  test(
    'stale metadata cannot undo a mandatory update; a newer rollback can',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppUpdateService.cacheKey, jsonEncode(manifest()));
      var response = manifest(build: 3, minimum: 0);
      final updates = AppUpdateService(
        client: MockClient(
          (_) async => http.Response(jsonEncode(response), 200),
        ),
      );
      await updates.refresh();
      expect(updates.required, isTrue);
      response = manifest(build: 5, minimum: 0);
      await updates.refresh(force: true);
      expect(updates.required, isFalse);
    },
  );

  testWidgets(
    'mandatory gate hides existing routes and cannot dismiss with Back',
    (tester) async {
      final updates = AppUpdateService()
        ..policy = UpdatePolicy.parse(manifest())
        ..installedBuild = 2
        ..installedVersion = '1.0.1';
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => AppUpdateGate(service: updates, child: child!),
          home: const Scaffold(body: Text('Start booking')),
        ),
      );
      expect(find.text('Start booking'), findsNothing);
      expect(find.byIcon(Icons.system_update_rounded), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byIcon(Icons.system_update_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('optional update leaves the booking UI accessible', (
    tester,
  ) async {
    final updates = AppUpdateService()
      ..policy = UpdatePolicy.parse(manifest(minimum: 0))
      ..installedBuild = 2;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AppUpdateGate(service: updates, child: child!),
        home: const Scaffold(body: Text('Start booking')),
      ),
    );
    expect(find.text('Start booking'), findsOneWidget);
  });
}
