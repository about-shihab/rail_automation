import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/seat_layout_challenge.dart';
import 'package:rail_automation/services/secure_store.dart';
import 'package:rail_automation/services/turnstile_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthSession(
    token: 'test-session',
    deviceId: 'device',
    deviceKey: 'key',
  );
  final train = ApiService.getMockResponse().trains[1];
  final seat = train.seatTypes.first;
  final layout = jsonEncode({
    'data': {
      'seatLayout': [
        {
          'floor_name': 'KA',
          'seat_floor': 1,
          'seat_fare': '400',
          'layout': [
            [
              {'seat_number': 'KA-1', 'ticket_id': 101, 'seat_availability': 1},
            ],
          ],
        },
      ],
    },
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('A cached token can only be taken once, including simultaneous reads', () async {
    final gate = TurnstileGate.instance;
    await gate.storeToken('unused-token');
    expect(
      await Future.wait([gate.takeCachedToken(), gate.takeCachedToken()]),
      ['unused-token', null],
    );
    for (final offset in [-300, 60]) {
      await SecureStore.write('rail_cft_token', 'invalid-time-token');
      await SecureStore.write(
        'rail_cft_token_time',
        '${DateTime.now().add(Duration(seconds: offset)).millisecondsSinceEpoch}',
      );
      expect(await gate.takeCachedToken(), isNull);
    }
  });

  test(
    'Only an explicit seat-layout challenge requests verification',
    () async {
      for (final status in [403, 422]) {
        for (final challenge in [false, true]) {
          await http.runWithClient(
            () async {
              await expectLater(
                ApiService.fetchSeatLayout(
                  tripId: 1,
                  tripRouteId: 2,
                  authSession: auth,
                ),
                throwsA(
                  challenge
                      ? isA<SeatLayoutChallenge>()
                      : isNot(isA<SeatLayoutChallenge>()),
                ),
              );
            },
            () => MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'message': challenge
                      ? 'TURNSTILE_VERIFICATION_FAILED'
                      : 'Invalid trip',
                }),
                status,
              ),
            ),
          );
        }
      }
    },
  );

  test(
    'Selecting and reserving seats reuses one layout and one submitted token',
    () async {
      var reads = 0;
      var mutations = 0;
      await TurnstileGate.instance.storeToken('unused-token');
      await http.runWithClient(
        () async {
          final first = BookingService.loadLayout(
            seat: seat,
            auth: auth,
            allowPrompt: false,
          );
          final second = BookingService.loadLayout(
            seat: seat,
            auth: auth,
            allowPrompt: false,
          );
          expect(identical(first, second), isTrue);
          final prepared = await first;
          expect(await TurnstileGate.instance.cachedToken(), isNull);
          final result = await BookingService.reserve(
            train: train,
            seat: seat,
            from: 'Dhaka',
            to: 'Chattogram',
            date: '30-Oct-2026',
            auth: auth,
            preparedLayout: prepared,
            selectedSeats: [
              prepared.layout.coaches.single.layout.single.single,
            ],
          );
          expect(result['status'], 'awaitingOtp');
          expect(reads, 1);
          expect(mutations, 1);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/seat-layout')) {
            reads++;
            expect(request.url.queryParameters['cft_response'], 'unused-token');
            return http.Response(
              layout,
              200,
              headers: {'x-action-token': 'railway-action'},
            );
          }
          if (request.url.path.endsWith('/handshake')) {
            return http.Response(
              '{"data":{"release_time_interval_in_minutes":300}}',
              200,
            );
          }
          if (request.url.path.endsWith('/reserve-seat')) {
            mutations++;
            final body = jsonDecode(request.body) as Map;
            expect(body.containsKey('action_token'), isFalse);
            expect(request.headers['X-Action-Token'], 'railway-action');
            return http.Response('{"data":{"ack":1}}', 200);
          }
          return http.Response('{"data":{"success":true}}', 200);
        }),
      );
    },
  );

  test('Reservation rejection never prompts or retries a mutation', () async {
    var mutations = 0;
    await TurnstileGate.instance.storeToken('fresh-mutation-test');
    await http.runWithClient(
      () async {
        await expectLater(
          BookingService.reserve(
            train: train,
            seat: seat,
            from: 'Dhaka',
            to: 'Chattogram',
            date: '30-Oct-2026',
            auth: auth,
            allowVerificationPrompt: true,
          ),
          throwsStateError,
        );
        expect(mutations, 1);
        expect(TurnstileGate.instance.isShowing, isFalse);
        expect((await BookingService.pending())?['status'], 'needsReview');
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/seat-layout')) {
          return http.Response(layout, 200);
        }
        if (request.url.path.endsWith('/handshake')) {
          return http.Response(
            '{"data":{"release_time_interval_in_minutes":300}}',
            200,
          );
        }
        mutations++;
        return http.Response(
          '{"message":"TURNSTILE_VERIFICATION_FAILED"}',
          422,
        );
      }),
    );
  });

  test('Background polling does not repeat a dismissed booking challenge after restart', () async {
    SharedPreferences.setMockInitialValues({
      MonitorService.preferenceKey: jsonEncode({
        'id': 'pending-booking',
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': '30-Oct-2026',
        'active': true,
        'expires': DateTime.now()
            .add(const Duration(hours: 8))
            .toIso8601String(),
        'bookingIntent': {'autoReserve': true, 'quantity': 1},
      }),
      'ticket_verification_pending-booking': 'presented',
    });
    await AuthSession.save(auth);
    final pro = ProService();
    final monitor = MonitorService(proService: pro, backgroundWorker: true);
    addTearDown(monitor.dispose);
    addTearDown(pro.dispose);
    var layoutRequests = 0;
    await http.runWithClient(
      () async {
        for (var i = 0; i < 3; i++) {
          await monitor.restore(startTimers: false);
          await monitor.checkNow();
          expect(monitor.needsTurnstile, isTrue);
        }
        expect(layoutRequests, 0);
        expect(TurnstileGate.instance.isShowing, isFalse);
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/seat-layout')) layoutRequests++;
        return http.Response(
          jsonEncode({
            'data': {
              'trains': [train.toJson()],
            },
          }),
          200,
        );
      }),
    );
  });
}
