import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/otp_verifier.dart';
import 'package:rail_automation/services/rail_api_client.dart';
import 'package:rail_automation/services/rail_api_config.dart';
import 'package:rail_automation/services/railway_credentials_rejected.dart';
import 'package:rail_automation/services/secure_store.dart';
import 'package:rail_automation/services/sms_service.dart';
import 'package:rail_automation/services/turnstile_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthSession(
    token: 'old-session',
    deviceId: 'device',
    deviceKey: 'key',
    phoneNumber: '01700000000',
  );
  var challenges = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AppConfig.instance.reloadCache();
    await AuthSession.save(auth);
    await AuthSession.saveUserCredentials('01700000000', 'test-password');
    challenges = 0;
    TurnstileGate.instance.workerAcquire = (_) async {
      challenges++;
      return 'fresh-cft';
    };
  });
  tearDown(() {
    TurnstileGate.instance.workerAcquire = null;
    SmsService().stopListening();
  });

  Future<http.Response> request({
    AuthSession? session,
    String method = 'GET',
  }) => RailApiClient.request(
    operation: 'search_trips',
    method: method,
    payload: {'from_city': 'Dhaka'},
    auth: session ?? auth,
  );

  test('401 refreshes securely and retries with new authorization', () async {
    final calls = <http.Request>[];
    await SecureStore.write('rail_action_token', 'old-action');
    await http.runWithClient(
      () async {
        expect((await request()).statusCode, 200);
      },
      () => MockClient((req) async {
        calls.add(req);
        if (req.url.path.endsWith('sign-in')) {
          expect(jsonDecode(req.body), {
            'mobile_number': '01700000000',
            'password': 'test-password',
            'cft_response': 'fresh-cft',
          });
          expect(req.headers.containsKey('Authorization'), isFalse);
          expect(req.headers['X-Device-Id'], 'device');
          return http.Response(
            '{"data":{"access_token":"new-session","success":true}}',
            200,
          );
        }
        return http.Response(
          '{}',
          req.headers['Authorization'] == 'Bearer old-session' ? 401 : 200,
        );
      }),
    );
    expect(calls.length, 3);
    expect(challenges, 1);
    expect((await AuthSession.load())!.token, 'new-session');
    expect(await SecureStore.read('rail_action_token'), isNull);
    expect(calls.last.headers.containsKey('X-Action-Token'), isFalse);
  });

  test('only explicit wrong credentials produce the login redirect error', () async {
    for (final message in [
      'Incorrect password',
      'Username or password is invalid',
      'Invalid credentials',
      'Mobile number or password does not match',
    ]) {
      expect(
        RailwayCredentialsRejected.isResponse(
          jsonEncode({
            'messages': {'message': message},
          }),
        ),
        isTrue,
      );
    }
    for (final message in [
      'Session expired',
      'Invalid access token',
      'TURNSTILE_VERIFICATION_FAILED',
      'Connection timed out',
      'Please sign in again',
    ]) {
      expect(
        RailwayCredentialsRejected.isResponse(jsonEncode({'message': message})),
        isFalse,
      );
      expect(RailwayCredentialsRejected.isError(StateError(message)), isFalse);
    }
    await http.runWithClient(
      () async {
        await expectLater(
          request(),
          throwsA(isA<RailwayCredentialsRejected>()),
        );
      },
      () => MockClient(
        (req) async => req.url.path.endsWith('sign-in')
            ? http.Response(
                '{"messages":{"message":"Username or password is incorrect"}}',
                422,
              )
            : http.Response('{}', 401),
      ),
    );
    expect((await AuthSession.load())!.token, auth.token);
  });

  test('expired JWT refreshes before sending the operation', () async {
    final jwt =
        'e30.${base64Url.encode(utf8.encode('{"exp":1}')).replaceAll('=', '')}.sig';
    final expired = AuthSession(
      token: jwt,
      deviceId: 'device',
      deviceKey: 'key',
      phoneNumber: '01700000000',
    );
    await AuthSession.save(expired);
    final paths = <String>[];
    await http.runWithClient(
      () async {
        expect((await request(session: expired)).statusCode, 200);
      },
      () => MockClient((req) async {
        paths.add(req.url.path);
        return http.Response(
          req.url.path.endsWith('sign-in')
              ? '{"data":{"access_token":"renewed"}}'
              : '{}',
          200,
        );
      }),
    );
    expect(paths.first, endsWith('sign-in'));
    expect(paths.length, 2);
  });

  test('concurrent invalid sessions share a single login', () async {
    var logins = 0;
    await http.runWithClient(
      () async {
        final responses = await Future.wait([request(), request()]);
        expect(responses.every((r) => r.statusCode == 200), isTrue);
      },
      () => MockClient((req) async {
        if (req.url.path.endsWith('sign-in')) {
          logins++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response('{"data":{"access_token":"renewed"}}', 200);
        }
        return http.Response(
          '{}',
          req.headers['Authorization'] == 'Bearer old-session' ? 401 : 200,
        );
      }),
    );
    expect(logins, 1);
  });

  test('explicit invalid-session 403 recovers while missing credentials stop login', () async {
    var logins = 0;
    await http.runWithClient(
      () async {
        expect((await request()).statusCode, 200);
      },
      () => MockClient((req) async {
        if (req.url.path.endsWith('sign-in')) {
          logins++;
          return http.Response('{"data":{"access_token":"renewed"}}', 200);
        }
        return req.headers['Authorization'] == 'Bearer old-session'
            ? http.Response('{"message":"Invalid session"}', 403)
            : http.Response('{}', 200);
      }),
    );
    expect(logins, 1);
    await AuthSession.save(auth);
    await AuthSession.clearSavedUserCredentials();
    await SecureStore.delete('rail_login_attempt_at');
    challenges = 0;
    var calls = 0;
    await http.runWithClient(
      () async {
        await expectLater(request(), throwsStateError);
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('{}', 401);
      }),
    );
    expect(calls, 1);
    expect(challenges, 0);
  });

  test(
    'DB intervals separate concurrent calls to the same operation',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConfig.cacheKey,
        jsonEncode({
          'api_operations': {
            'search_trips': {'min_interval_seconds': 1},
          },
        }),
      );
      await AppConfig.instance.reloadCache();
      final times = <DateTime>[];
      await http.runWithClient(
        () async {
          await Future.wait([request(), request()]);
        },
        () => MockClient((_) async {
          times.add(DateTime.now());
          return http.Response('{}', 200);
        }),
      );
      expect(times.length, 2);
      expect(
        times[1].difference(times[0]).inMilliseconds,
        greaterThanOrEqualTo(950),
      );
    },
  );

  test(
    'repeated rejection is bounded and login cooldown prevents storms',
    () async {
      var logins = 0;
      await http.runWithClient(
        () async {
          await expectLater(request(), throwsStateError);
          await expectLater(request(), throwsStateError);
        },
        () => MockClient((req) async {
          if (req.url.path.endsWith('sign-in')) {
            logins++;
            return http.Response('{"data":{"access_token":"renewed"}}', 200);
          }
          return http.Response('{}', 401);
        }),
      );
      expect(logins, 1);
    },
  );

  test(
    'generic 403 and unknown mutation outcomes never trigger login or replay',
    () async {
      for (final response in [
        http.Response('Cloudflare denied', 403),
        http.Response('{}', 500),
      ]) {
        var count = 0;
        await http.runWithClient(
          () async {
            expect(
              (await request(method: 'PATCH')).statusCode,
              response.statusCode,
            );
          },
          () => MockClient((_) async {
            count++;
            return response;
          }),
        );
        expect(count, 1);
      }
      var count = 0;
      await http.runWithClient(
        () async {
          await expectLater(
            request(method: 'PATCH'),
            throwsA(isA<TimeoutException>()),
          );
        },
        () => MockClient((_) async {
          count++;
          throw TimeoutException('unknown outcome');
        }),
      );
      expect(count, 1);
      expect(challenges, 0);
    },
  );

  test('DB endpoint and typed payload template are used at runtime', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConfig.cacheKey,
      jsonEncode({
        'api_operations': {
          'search_trips': {
            'url': '${RailApiConfig.baseUrl}/bookings/search-configured',
            'payload': {'origin': '{{from_city}}', 'enabled': true},
          },
        },
      }),
    );
    await AppConfig.instance.reloadCache();
    await http.runWithClient(
      () async {
        await request();
      },
      () => MockClient((req) async {
        expect(req.url.path, endsWith('search-configured'));
        expect(req.url.queryParameters, {'origin': 'Dhaka', 'enabled': 'true'});
        return http.Response('{}', 200);
      }),
    );
    expect(
      RailApiConfig.render(
        {'ids': '{{ids}}'},
        {
          'ids': [1, 2],
        },
      ),
      {
        'ids': [1, 2],
      },
    );
    final validated = RailApiConfig.validate({
      'sign_in': {
        'url': 'https://untrusted.example/login',
        'payload': {'password': 'literal-secret'},
      },
    });
    expect(validated['sign_in'], isEmpty);
  });

  test('missing SMS permission persists manual OTP fallback', () async {
    const channel = MethodChannel('com.example.rail_automation/sms');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await BookingService.save({
      'id': 'pending',
      'status': 'awaitingOtp',
      'autoVerify': true,
      'credit_deducted': true,
    });
    await OtpVerifier.listen();
    // Availability callbacks finish asynchronously after the native response.
    for (var i = 0; i < 20; i++) {
      if ((await BookingService.pending())?['autoVerify'] == false) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect((await BookingService.pending())!['autoVerify'], isFalse);
    expect((await BookingService.pending())!['status'], 'awaitingOtp');
  });
}
