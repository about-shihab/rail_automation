import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/notification_service.dart';
import 'package:rail_automation/services/seat_layout_challenge.dart';
import 'package:rail_automation/services/turnstile_gate.dart';
import 'package:rail_automation/widgets/turnstile_host.dart';

import 'support/fake_inapp_webview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = '0x4AAAAACustomSeatKey1234';
  const iosAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148';
  late FakeInAppWebViewPlatform browser;
  final auth = AuthSession(
    token: 'test-session',
    deviceId: 'device',
    deviceKey: 'key',
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppConfig.cacheKey: jsonEncode({
        'api_headers': {
          'User-Agent': 'desktop-override',
          'sec-ch-ua-platform': '"Windows"',
        },
        'turnstile_site_keys': {'seat_layout': key},
        'api_operations': {
          'seat_layout': {
            'payload': {
              'trip_id': '{{trip_id}}',
              'trip_route_id': '{{trip_route_id}}',
            },
          },
        },
      }),
    });
    FlutterSecureStorage.setMockInitialValues({});
    await AppConfig.instance.reloadCache();
    await AuthSession.save(auth);
    browser = FakeInAppWebViewPlatform()..userAgent = iosAgent;
    InAppWebViewPlatform.instance = browser;
  });

  testWidgets(
    'a completed browser challenge reaches the layout API once with its own identity and configured key',
    (tester) async {
      var requests = 0;
      http.Request? submitted;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: NotificationService.navigatorKey,
              builder: (_, child) => TurnstileHost(child: child!),
              home: const Scaffold(),
            ),
          );
          await tester.pump();
          final layout = BookingService.loadLayout(
            seat: ApiService.getMockResponse().trains[1].seatTypes.first,
            auth: auth,
          );
          for (var i = 0; i < 60 && browser.controller.executions == 0; i++) {
            await tester.pump();
          }
          expect(
            requests,
            0,
            reason: 'No API request is sent before the challenge completes',
          );
          expect(browser.controller.executions, 1);
          expect(browser.controller.scripts.last, contains(key));
          // This simulates the WKWebView callback; it does not validate a live CFT token.
          browser.controller.send(
            '{"status":"SUCCESS","token":"completed-test-challenge"}',
          );
          for (var i = 0; i < 60 && requests == 0; i++) {
            await tester.pump();
          }
          final prepared = await layout;
          expect(prepared.layout.coaches, isEmpty);
          expect(requests, 1);
          final request = submitted!;
          expect(
            request.url.queryParameters['cft_response'],
            'completed-test-challenge',
            reason: 'The configured payload template must preserve the real runtime token',
          );
          final headers = {
            for (final entry in request.headers.entries)
              entry.key.toLowerCase(): entry.value,
          };
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            expect(headers['user-agent'], iosAgent);
            expect(headers.keys.any((k) => k.startsWith('sec-ch-')), isFalse);
          } else {
            expect(headers['user-agent'], 'desktop-override');
            expect(headers['sec-ch-ua-platform'], '"Windows"');
          }
          expect(await TurnstileGate.instance.cachedToken(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          requests++;
          submitted = request;
          return http.Response('{"data":{"seatLayout":[]}}', 200);
        }),
      );
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  test('an empty challenge result never calls the seat-layout API', () async {
    final gate = TurnstileGate.instance;
    gate.workerAcquire = (_) async => '';
    addTearDown(() => gate.workerAcquire = null);
    var calls = 0;
    await expectLater(
      gate.guardSeatLayout<void>(
        run: (_) async {
          calls++;
        },
      ),
      throwsA(isA<SeatLayoutChallenge>()),
    );
    expect(calls, 0);
  });
}
