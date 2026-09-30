import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rail_automation/views/watch_options_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/booking_intent.dart';
import 'package:rail_automation/models/seat_type.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/app_config.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/secure_store.dart';
import 'package:rail_automation/services/sms_service.dart';
import 'package:rail_automation/models/trip_record.dart';
import 'package:rail_automation/services/trip_history_service.dart';
import 'package:rail_automation/services/credit_service.dart';
import 'package:rail_automation/models/seat_layout.dart';
import 'package:rail_automation/services/web_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  final auth = AuthSession(
    token: 'real-shaped-test-session',
    deviceId: 'device',
    deviceKey: 'key',
  );
  final train = ApiService.getMockResponse().trains[1];
  final seat = train.seatTypes.first;

  Map<String, dynamic> checkoutState(List<Map<String, dynamic>> seats) => {
    'train': train.toJson(),
    'seatClass': seat.toJson(),
    'coach': {'seat_fare': '450.00'},
    'seats': seats,
  };

  test('checkout repairs legacy seat fares using the reserved coach', () {
    final state = checkoutState([
      {'ticket_id': 101},
      {'ticket_id': 102},
    ]);
    final storage = BookingService.webStorage(state, '01700000000');
    final purchase = jsonDecode(storage['initialPurchaseData01700000000']);
    final seats = purchase['reservedSeats'] as List;
    expect(seats.map((s) => s['fare']), [450, 450]);
    expect(seats.map((s) => s['selected_seat_class']), [seat.type, seat.type]);
    expect(seats.fold<num>(0, (total, s) => total + (s['fare'] as num)), 900);
    expect(state['seats'][0].containsKey('fare'), isFalse);
  });

  test('checkout preserves per-seat fares and rejects invalid prices', () {
    final state = checkoutState([
      {'ticket_id': 101, 'fare': '595.50'},
    ]);
    final purchase = jsonDecode(
      BookingService.webStorage(
        state,
        '01700000000',
      )['initialPurchaseData01700000000'],
    );
    expect(purchase['reservedSeats'][0]['fare'], 595.5);
    for (final invalid in ['NaN', 'Infinity', '', '-1', 'unknown']) {
      state['seats'][0]['fare'] = invalid;
      expect(
        () => BookingService.webStorage(state, '01700000000'),
        throwsStateError,
      );
    }
    state['seats'][0].remove('fare');
    state['coach'].remove('seat_fare');
    expect(
      () => BookingService.webStorage(state, '01700000000'),
      throwsStateError,
    );
  });

  testWidgets('auto-reserve starts without entering a fare', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.example.rail_automation/sms'),
      (_) async => false,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.example.rail_automation/sms'),
        null,
      ),
    );
    BookingIntent? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showWatchOptions(context);
              },
              child: const Text('Watch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Watch'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.ensureVisible(find.text('Start auto-booking'));
    await tester.tap(find.text('Start auto-booking'));
    await tester.pumpAndSettle();
    expect(result?.autoReserve, isTrue);
    expect(result?.maxFare, isNull);
    expect(result?.quantity, 1);
  });

  test('operational settings reject invalid database values', () {
    final config = AppConfig.validate({
      'poll_interval_seconds': 0,
      'max_seats': 99,
      'otp_length': '6',
      'stations': [null],
    });
    expect(config['poll_interval_seconds'], 120);
    expect(config['max_seats'], 4);
    expect(config['otp_length'], 6);
    expect(
      AppConfig.validate({
        'poll_interval_seconds': 180,
      })['poll_interval_seconds'],
      180,
    );
  });
  test(
    'credential migration removes plaintext and preserves special characters',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('br_saved_password', "a'\\b\npassword ");
      expect(
        (await AuthSession.getSavedUserCredentials())['password'],
        "a'\\b\npassword ",
      );
      expect(prefs.containsKey('br_saved_password'), isFalse);
      await AuthSession.saveUserCredentials('01700000000', ' new secret ');
      expect(
        (await AuthSession.getSavedUserCredentials())['password'],
        ' new secret ',
      );
    },
  );
  test('JWT exp has no one-day grace period', () {
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'exp':
              DateTime.now()
                  .subtract(const Duration(seconds: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        }),
      ),
    );
    expect(AuthSession.isJwtExpired('header.$payload.signature'), isTrue);
  });
  test('random selection obeys quantity, class and fare constraints', () {
    const intent = BookingIntent(autoReserve: true, quantity: 4, maxFare: 500);
    final chosen = intent.choose(
      ApiService.getMockResponse().trains,
      random: Random(7),
    );
    expect(chosen?.$2.type, 'S_CHAIR');
    expect(chosen?.$1.tripNumber, 'CHATTALA EXPRESS (802)');
    expect(intent.choose([train], seatClass: 'SNIGDHA'), isNull);
  });
  test('random class chooses whichever seat class is available across all returned seat types', () {
    expect(SeatType.randomClass.displayName, 'Random Class (Any Available)');
    expect(ApiService.requestSeatClass('RANDOM'), 'SNIGDHA');
    expect(ApiService.requestSeatClass('ALL'), 'SNIGDHA');

    const intent = BookingIntent(autoReserve: true, quantity: 1);
    final mockTrains = ApiService.getMockResponse().trains;

    // Both 'RANDOM', 'ALL', and null evaluate all seat types and pick an available one
    final chosenRandom = intent.choose(mockTrains, seatClass: 'RANDOM', random: Random(42));
    final chosenAll = intent.choose(mockTrains, seatClass: 'ALL', random: Random(42));
    final chosenNull = intent.choose(mockTrains, seatClass: null, random: Random(42));

    expect(chosenRandom, isNotNull);
    expect(chosenAll, isNotNull);
    expect(chosenNull, isNotNull);
    expect(chosenRandom?.$2.seatCounts.online, greaterThanOrEqualTo(1));
    expect(chosenAll?.$2.seatCounts.online, greaterThanOrEqualTo(1));
  });
  test('SMS parser ignores unrelated senders and non-OTP messages', () {
    expect(SmsService.extractOtp('BANK', 'OTP 123456', ['RAILWAY'], 6), isNull);
    expect(
      SmsService.extractOtp('RAILWAY', 'Ticket 123456', ['RAILWAY'], 6),
      isNull,
    );
    expect(
      SmsService.extractOtp('railway', 'OTP: 012345', ['RAILWAY'], 6),
      '012345',
    );
  });
  test('credential injection only allows the exact HTTPS railway origin', () {
    expect(
      WebSessionService.isRailwayUrl('https://eticket.railway.gov.bd/login'),
      isTrue,
    );
    expect(
      WebSessionService.isRailwayUrl(
        'https://eticket.railway.gov.bd.evil.test',
      ),
      isFalse,
    );
    expect(
      WebSessionService.isRailwayUrl('http://eticket.railway.gov.bd'),
      isFalse,
    );
  });
  test('failed seat layout never falls back to mock inventory', () async {
    await http.runWithClient(
      () => expectLater(
        ApiService.fetchSeatLayout(
          tripId: 1,
          tripRouteId: 2,
          authSession: auth,
        ),
        throwsStateOrException,
      ),
      () => MockClient((_) async => http.Response('{}', 403)),
    );
  });
  test(
    'seat layout sends single device headers and uses server availability',
    () async {
      await http.runWithClient(
        () async {
          final result = await ApiService.fetchSeatLayout(
            tripId: 8608105,
            tripRouteId: 59340076,
            authSession: auth,
            cftResponse: 'fresh-verification',
          );
          expect(result.totalAvailableSeats, 1);
          expect(
            result.coaches.single.layout.single.single.seatNumber,
            'DA-26',
          );
          expect(await SecureStore.read('rail_action_token'), 'next-token');
        },
        () => MockClient((request) async {
          expect(request.url.queryParameters, {
            'trip_id': '8608105',
            'trip_route_id': '59340076',
            'cft_response': 'fresh-verification',
          });
          expect(request.headers['X-Device-Id'], 'device');
          expect(request.headers['X-Device-Key'], 'key');
          return http.Response(
            jsonEncode({
              'data': {
                'seatLayout': [
                  {
                    'floor_name': 'DA',
                    'seat_fare': '450.00',
                    'layout': [
                      [
                        {
                          'isHidden': false,
                          'seat_availability': 1,
                          'seat_number': 'DA-26',
                          'ticket_id': 626102685,
                          'ticket_type': 1,
                        },
                      ],
                    ],
                  },
                ],
              },
            }),
            200,
            headers: {'x-action-token': 'next-token'},
          );
        }),
      );
    },
  );
  test('verification responses do not overwrite the action token', () async {
    await SecureStore.write('rail_action_token', 'existing');
    await http.runWithClient(
      () => expectLater(
        ApiService.fetchSeatLayout(
          tripId: 1,
          tripRouteId: 2,
          authSession: auth,
        ),
        throwsA(
          predicate((e) => e.toString().contains('official booking page')),
        ),
      ),
      () => MockClient(
        (_) async => http.Response(
          '<html>Verify</html>',
          200,
          headers: {'x-action-token': 'invalid'},
        ),
      ),
    );
    expect(await SecureStore.read('rail_action_token'), 'existing');
  });

  Map<String, dynamic> layout() => {
    'data': {
      'seatLayout': [
        {
          'floor_name': 'KA',
          'seat_floor': 1,
          'seat_fare': '400',
          'seat_availability': true,
          'layout': [
            [
              {'seat_number': 'KA-1', 'ticket_id': 101, 'seat_availability': 1},
              {'seat_number': 'KA-2', 'ticket_id': 102, 'seat_availability': 1},
            ],
          ],
        },
      ],
    },
  };
  Future<Map<String, dynamic>> reserve() => BookingService.reserve(
    train: train,
    seat: seat,
    from: 'Dhaka',
    to: 'Chattogram',
    date: '30-Sep-2026',
    auth: auth,
    quantity: 2,
    maxFare: 600,
  );

  test('cancellation after layout prevents reservation mutations', () async {
    await http.runWithClient(
      () async {
        await expectLater(
          BookingService.reserve(
            train: train,
            seat: seat,
            from: 'Dhaka',
            to: 'Chattogram',
            date: '30-Sep-2026',
            auth: auth,
            canReserve: () async => false,
          ),
          throwsStateError,
        );
        expect(await BookingService.pending(), isNull);
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/handshake'))
          return http.Response(
            '{"data":{"release_time_interval_in_minutes":300}}',
            200,
          );
        if (request.url.path.endsWith('/seat-layout'))
          return http.Response(jsonEncode(layout()), 200);
        fail('Cancelled search sent a booking mutation');
      }),
    );
  });

  test(
    'reservation requires server acknowledgements and verified OTP',
    () async {
      final paths = <String>[];
      await http.runWithClient(
        () async {
          final state = await reserve();
          expect(state['status'], 'awaitingOtp');
          expect(state['confirmedTicketIds'], hasLength(2));
          expect((state['seats'] as List).map((s) => s['fare']), [
            '400',
            '400',
          ]);
          expect(
            DateTime.parse(state['expiresAt']).isAfter(DateTime.now()),
            isTrue,
          );
          final verified = await BookingService.verifyOtp('012345', auth);
          expect(verified['status'], 'readyForPayment');
          final storage = BookingService.webStorage(verified, '01700000000');
          expect(storage['continue_booking_otp_verified'], '1');
          expect(storage['confirm_booking_otp'], '012345');
          await expectLater(reserve(), throwsStateError);
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          final path = request.url.path;
          if (path.endsWith('/handshake'))
            return http.Response(
              jsonEncode({
                'data': {'release_time_interval_in_minutes': 300},
              }),
              200,
            );
          if (path.endsWith('/seat-layout'))
            return http.Response(
              jsonEncode(layout()),
              200,
              headers: {'x-action-token': 'token-a'},
            );
          if (path.endsWith('/reserve-seat')) {
            expect(request.method, 'PATCH');
            expect(request.headers['X-Action-Token'], isNotEmpty);
            return http.Response(
              '{"data":{"ack":1}}',
              200,
              headers: {'x-action-token': 'token-b'},
            );
          }
          if (path.endsWith('/verify-otp'))
            expect(jsonDecode(request.body)['otp'], '012345');
          return http.Response('{"data":{"success":true}}', 200);
        }),
      );
      expect(paths.where((p) => p.endsWith('/reserve-seat')), hasLength(2));
      expect(paths.where((p) => p.endsWith('/verify-otp')), hasLength(1));
    },
  );

  test('auto-book reservation to awaitingOtp costs 1 credit, but completion does not double deduct', () async {
    final creditService = CreditService();
    creditService.setCreditsForTesting(3);

    await http.runWithClient(
      () async {
        final state = await BookingService.reserve(
          train: train,
          seat: seat,
          from: 'Dhaka',
          to: 'Chattogram',
          date: '30-Sep-2026',
          auth: auth,
          quantity: 2,
          maxFare: 600,
          isAutoBook: true,
        );
        expect(state['status'], 'awaitingOtp');
        expect(state['isAutoBook'], isTrue);
        expect(state['credit_deducted'], isTrue);
        // Credit deducted by 1 upon sending OTP
        expect(creditService.credits, 2);

        // Later when booking completes successfully, it should NOT double deduct
        final completed = await BookingService.completeSuccessfulBooking(reservation: state);
        expect(completed, isTrue);
        expect(creditService.credits, 2, reason: 'Credit must not be double deducted if already deducted at OTP send');
      },
      () => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/handshake')) {
          return http.Response(
            jsonEncode({'data': {'release_time_interval_in_minutes': 300}}),
            200,
          );
        }
        if (path.endsWith('/seat-layout')) {
          return http.Response(jsonEncode(layout()), 200, headers: {'x-action-token': 'token-a'});
        }
        if (path.endsWith('/reserve-seat')) {
          return http.Response('{"data":{"ack":1}}', 200, headers: {'x-action-token': 'token-b'});
        }
        return http.Response('{"data":{"success":true}}', 200);
      }),
    );
  });

  test('reservation supports selecting seats across multiple coaches', () async {
    final multiCoachLayout = {
      'data': {
        'seatLayout': [
          {
            'floor_name': 'KA',
            'seat_floor': 1,
            'seat_fare': '400',
            'seat_availability': true,
            'layout': [
              [
                {'seat_number': 'KA-1', 'ticket_id': 101, 'seat_availability': 1},
              ],
            ],
          },
          {
            'floor_name': 'KHA',
            'seat_floor': 2,
            'seat_fare': '400',
            'seat_availability': true,
            'layout': [
              [
                {'seat_number': 'KHA-1', 'ticket_id': 201, 'seat_availability': 1},
              ],
            ],
          },
        ],
      },
    };

    final selectedSeats = [
      SeatItem(
        isHidden: false,
        seatAvailability: 1,
        seatNumber: 'KA-1',
        ticketId: 101,
        ticketType: 1,
      ),
      SeatItem(
        isHidden: false,
        seatAvailability: 1,
        seatNumber: 'KHA-1',
        ticketId: 201,
        ticketType: 1,
      ),
    ];

    await http.runWithClient(
      () async {
        final state = await BookingService.reserve(
          train: train,
          seat: seat,
          from: 'Dhaka',
          to: 'Chattogram',
          date: '30-Sep-2026',
          auth: auth,
          quantity: 2,
          selectedSeats: selectedSeats,
        );
        expect(state['coach_names'], 'KA, KHA');
        expect(state['seats'], hasLength(2));
        final seatFloors = (state['seats'] as List).map((s) => s['floor_name']).toList();
        expect(seatFloors, containsAll(['KA', 'KHA']));
      },
      () => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/handshake'))
          return http.Response(
            jsonEncode({'data': {'release_time_interval_in_minutes': 300}}),
            200,
          );
        if (path.endsWith('/seat-layout'))
          return http.Response(
            jsonEncode(multiCoachLayout),
            200,
            headers: {'x-action-token': 'token-mc'},
          );
        if (path.endsWith('/reserve-seat'))
          return http.Response(
            '{"data":{"ack":1}}',
            200,
            headers: {'x-action-token': 'token-ack'},
          );
        return http.Response('{"data":{"success":true}}', 200);
      }),
    );
  });
  test(
    'unknown mutation outcome persists and blocks duplicate booking',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(reserve(), throwsStateError);
          expect((await BookingService.pending())?['status'], 'needsReview');
          await expectLater(reserve(), throwsStateError);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/handshake'))
            return http.Response(
              '{"data":{"release_time_interval_in_minutes":300}}',
              200,
            );
          if (request.url.path.endsWith('/seat-layout'))
            return http.Response(jsonEncode(layout()), 200);
          return http.Response('{}', 503);
        }),
      );
    },
  );
  test(
    'failed OTP never enables payment or stores the rejected code',
    () async {
      await BookingService.save({
        'status': 'awaitingOtp',
        'seatClass': {'trip_id': 1, 'trip_route_id': 2},
        'seats': [
          {'ticket_id': 101},
        ],
      });
      await http.runWithClient(
        () => expectLater(
          BookingService.verifyOtp('123456', auth),
          throwsStateError,
        ),
        () => MockClient(
          (_) async => http.Response('{"data":{"success":false}}', 200),
        ),
      );
      expect((await BookingService.pending())?['status'], 'awaitingOtp');
      expect(
        await SecureStore.read(BookingService.storageKey),
        isNot(contains('123456')),
      );
    },
  );

  test('reservation automatically clears after 5 minutes', () async {
    // 1. Fresh reservation is active
    await BookingService.save({
      'status': 'awaitingOtp',
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String(),
      'seatClass': {'trip_id': 1, 'trip_route_id': 2},
      'seats': [{'ticket_id': 101}],
    });
    expect(await BookingService.pending(), isNotNull);

    // 2. Reservation started 5 minutes and 1 second ago is automatically cleared
    await BookingService.save({
      'status': 'awaitingOtp',
      'startedAt': DateTime.now().subtract(const Duration(minutes: 5, seconds: 1)).toUtc().toIso8601String(),
      'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
      'seatClass': {'trip_id': 1, 'trip_route_id': 2},
      'seats': [{'ticket_id': 101}],
    });
    expect(await BookingService.pending(), isNull);
    expect(await SecureStore.read(BookingService.storageKey), isNull);

    // 3. Reservation with expired expiresAt is automatically cleared
    await BookingService.save({
      'status': 'awaitingOtp',
      'startedAt': DateTime.now().subtract(const Duration(minutes: 2)).toUtc().toIso8601String(),
      'expiresAt': DateTime.now().subtract(const Duration(seconds: 5)).toUtc().toIso8601String(),
      'seatClass': {'trip_id': 1, 'trip_route_id': 2},
      'seats': [{'ticket_id': 101}],
    });
    expect(await BookingService.pending(), isNull);
    expect(await SecureStore.read(BookingService.storageKey), isNull);
  });

  test('TripHistoryService tracks successful, awaitingOtp, expired, and failed bookings', () async {
    final history = TripHistoryService();
    await history.clearHistory();

    final trip1 = TripRecord(
      id: 'trip_1',
      trainName: 'PARJOTAK EXPRESS (816)',
      fromCity: 'Dhaka',
      toCity: 'Chattogram',
      dateOfJourney: '06-Oct-2026',
      seatClass: 'SNIGDHA',
      seatNumbers: ['CHA-12', 'CHA-13'],
      coachName: 'CHA',
      totalFare: 1640.0,
      status: TripBookingStatus.successful,
      createdAt: DateTime.now(),
      isAutoBook: true,
    );

    final trip2 = TripRecord(
      id: 'trip_2',
      trainName: 'SONAR BANGLA EXPRESS (788)',
      fromCity: 'Dhaka',
      toCity: 'Chattogram',
      dateOfJourney: '06-Oct-2026',
      seatClass: 'S_CHAIR',
      seatNumbers: [],
      status: TripBookingStatus.failed,
      failureReason: 'Seat layout rejected (422): Turnstile verification required',
      createdAt: DateTime.now(),
      isAutoBook: true,
    );

    await history.recordTrip(trip1);
    await history.recordTrip(trip2);

    expect(history.trips.length, 2);
    expect(history.successfulTrips.length, 1);
    expect(history.failedTrips.length, 1);
    expect(history.successfulTrips.first.trainName, 'PARJOTAK EXPRESS (816)');
    expect(history.failedTrips.first.failureReason, contains('422'));

    // Update trip1 status to expired when 5-min timeout hits
    await history.updateTripStatus('trip_1', TripBookingStatus.expired, failureReason: 'Reservation timed out after 5 minutes');
    expect(history.failedTrips.length, 2);
    expect(history.successfulTrips.length, 0);
  });
}

final throwsStateOrException = throwsA(
  anyOf(isA<StateError>(), isA<Exception>()),
);
