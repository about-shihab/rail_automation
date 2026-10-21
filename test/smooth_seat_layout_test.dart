import 'dart:async';

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
import 'package:rail_automation/services/rail_request_pacer.dart';
import 'package:rail_automation/services/seat_layout_challenge.dart';
import 'package:rail_automation/services/turnstile_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gate = TurnstileGate.instance;
  final auth = AuthSession(
    token: 'test-session',
    deviceId: 'device',
    deviceKey: 'key',
    phoneNumber: '01700000000',
  );
  final seat = ApiService.getMockResponse().trains[1].seatTypes.first;
  var generated = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AppConfig.instance.reloadCache();
    generated = 0;
    NotificationService().appVisible = true;
    gate.workerAcquire = (_) async => 'fresh-token-${++generated}';
  });
  tearDown(() {
    gate.workerAcquire = null;
    NotificationService().appVisible = false;
  });
  Future<BookingLayout> load() =>
      BookingService.loadLayout(seat: seat, auth: auth);

  for (final status in [200, 400, 403, 422]) {
    test(
      'explicit CFT rejection ($status) refreshes once and retries with a different token',
      () async {
        final submitted = <String?>[];
        await http.runWithClient(
          () async {
            final first = load();
            final second = load();
            expect(identical(first, second), isTrue);
            await Future.wait([first, second]);
          },
          () => MockClient((request) async {
            submitted.add(request.url.queryParameters['cft_response']);
            return submitted.length == 1
                ? http.Response(
                    '{"messages":{"errors":{"cft_response":["Invalid token"]}}}',
                    status,
                  )
                : http.Response('{"data":{"seatLayout":[]}}', 200);
          }),
        );
        expect(submitted, ['fresh-token-1', 'fresh-token-2']);
        expect(generated, 2);
        expect(await gate.cachedToken(), isNull);
      },
    );
  }

  test(
    'plain CFT verification failure refreshes once without a login attempt',
    () async {
      final submitted = <String?>[];
      await http.runWithClient(
        () => load(),
        () => MockClient((request) async {
          expect(request.url.path, endsWith('seat-layout'));
          submitted.add(request.url.queryParameters['cft_response']);
          return submitted.length == 1
              ? http.Response('{"message":"CFT verification failed"}', 403)
              : http.Response('{"data":{"seatLayout":[]}}', 200);
        }),
      );
      expect(submitted, ['fresh-token-1', 'fresh-token-2']);
      expect(generated, 2);
    },
  );

  test('403 invalid token with CFT context refreshes verification without signing in', () async {
    final paths = <String>[];
    await http.runWithClient(
      () => load(),
      () => MockClient((request) async {
        paths.add(request.url.path);
        return paths.length == 1
            ? http.Response(
                '{"message":"Invalid token","errors":{"cft_response":["Invalid"]}}',
                403,
              )
            : http.Response('{"data":{"seatLayout":[]}}', 200);
      }),
    );
    expect(paths, hasLength(2));
    expect(paths.every((path) => path.endsWith('seat-layout')), isTrue);
    expect(generated, 2);
  });

  test(
    'a rejected prepared token is replaced without being submitted twice',
    () async {
      await gate.storeToken('prepared-old-token');
      final submitted = <String?>[];
      await http.runWithClient(
        () => load(),
        () => MockClient((request) async {
          submitted.add(request.url.queryParameters['cft_response']);
          return submitted.length == 1
              ? http.Response('{"message":"timeout-or-duplicate"}', 422)
              : http.Response('{"data":{"seatLayout":[]}}', 200);
        }),
      );
      expect(submitted, ['prepared-old-token', 'fresh-token-1']);
      expect(generated, 1);
    },
  );

  test(
    'two rejected tokens stop rather than creating an automatic retry loop',
    () async {
      var requests = 0;
      await http.runWithClient(
        () => expectLater(
          load(),
          throwsA(
            isA<SeatLayoutChallenge>().having(
              (e) => e.tokenRejected,
              'token rejected',
              true,
            ),
          ),
        ),
        () => MockClient((_) async {
          requests++;
          return http.Response(
            '{"message":"TURNSTILE_VERIFICATION_FAILED"}',
            422,
          );
        }),
      );
      expect(requests, 2);
      expect(generated, 2);
    },
  );

  test('a backgrounded worker defers verification instead of generating another token', () async {
    var requests = 0;
    await http.runWithClient(
      () => expectLater(
        load(),
        throwsA(
          isA<SeatLayoutChallenge>().having(
            (e) => e.requiresForeground,
            'requires app open',
            true,
          ),
        ),
      ),
      () => MockClient((_) async {
        requests++;
        NotificationService().appVisible = false;
        return http.Response('{"message":"Invalid CFT token"}', 422);
      }),
    );
    expect(requests, 1);
    expect(generated, 1);
  });

  for (final status in [429, 500]) {
    test('server failure ($status) does not start a token refresh', () async {
      var requests = 0;
      await http.runWithClient(
        () => expectLater(
          load(),
          throwsA(
            status == 429
                ? isA<RailwayRateLimited>()
                : isNot(isA<SeatLayoutChallenge>()),
          ),
        ),
        () => MockClient((_) async {
          requests++;
          return http.Response('{"message":"Busy"}', status);
        }),
      );
      expect(requests, 1);
      expect(generated, 1);
    });
  }

  test(
    'session recovery refreshes the layout token before retrying seats',
    () async {
      await AuthSession.save(auth);
      await AuthSession.saveUserCredentials('01700000000', 'test-password');
      gate.workerAcquire = (label) async =>
          '${label == 'Railway login' ? 'login' : 'seat'}-proof-${++generated}';
      final seats = <http.Request>[];
      final logins = <http.Request>[];
      await http.runWithClient(
        () => load(),
        () => MockClient((request) async {
          if (request.url.path.endsWith('sign-in')) {
            logins.add(request);
            return http.Response(
              '{"data":{"access_token":"renewed-session"}}',
              200,
            );
          }
          seats.add(request);
          return seats.length == 1
              ? http.Response('{}', 401)
              : http.Response('{"data":{"seatLayout":[]}}', 200);
        }),
      );
      expect(seats, hasLength(2));
      expect(logins, hasLength(1));
      expect(seats.map((r) => r.url.queryParameters['cft_response']), [
        'seat-proof-1',
        'seat-proof-3',
      ]);
      expect(seats.last.headers['Authorization'], 'Bearer renewed-session');
      expect(logins.single.body, contains('login-proof-2'));
    },
  );

  test('unknown network outcomes do not replay the token', () async {
    var requests = 0;
    await http.runWithClient(
      () => expectLater(load(), throwsA(isA<TimeoutException>())),
      () => MockClient((_) async {
        requests++;
        throw TimeoutException('no response');
      }),
    );
    expect(requests, 1);
    expect(generated, 1);
  });
}
