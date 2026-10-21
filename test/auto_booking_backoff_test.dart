import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/train_trip.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/monitor_service.dart';
import 'package:rail_automation/services/pro_service.dart';
import 'package:rail_automation/services/rail_api_client.dart';
import 'package:rail_automation/services/turnstile_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final train = TrainTrip.fromJson({
    ...ApiService.getMockResponse().trains[1].toJson(),
    'departure_full_date': DateFormat('yyyy-MM-dd')
        .format(DateTime.now().add(const Duration(days: 1))),
    'departure_date_time_jd': '',
    'departure_date_time': '23:00',
  });
  late MonitorService monitor;
  late ProService pro;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({
      MonitorService.preferenceKey: jsonEncode({
        'id': 'paced-auto-book',
        'from': 'Dhaka',
        'to': 'Chattogram',
        'date': DateFormat(
          'dd-MMM-yyyy',
          'en_US',
        ).format(DateTime.now().add(const Duration(days: 1))),
        'active': true,
        'expires': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
        'bookingIntent': {'autoReserve': true, 'quantity': 1},
      }),
    });
    FlutterSecureStorage.setMockInitialValues({});
    await AuthSession.save(
      AuthSession(token: 'test-session', deviceId: 'device', deviceKey: 'key'),
    );
    TurnstileGate.instance.workerAcquire = (_) async => 'fresh-test-token';
    pro = ProService();
    monitor = MonitorService(proService: pro, backgroundWorker: true);
    await monitor.restore(startTimers: false);
  });
  tearDown(() {
    monitor.dispose();
    pro.dispose();
    TurnstileGate.instance.workerAcquire = null;
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'iOS foreground auto-booking waits out a 429 without sending more searches',
    () async {
      monitor.dispose();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      monitor = MonitorService(proService: pro);
      await monitor.restore(startTimers: false);
      var searches = 0;
      var handshakes = 0;
      await http.runWithClient(
        () async {
          await monitor.checkNow();
          expect(searches, 1);
          expect(handshakes, 1);
          expect(monitor.isMonitoring, isTrue);
          expect(
            RailApiClient.cooldownRemaining,
            greaterThan(const Duration(seconds: 44)),
          );
          expect(
            monitor.nextCheckDelay(),
            greaterThanOrEqualTo(RailApiClient.cooldownRemaining),
          );
          await monitor.checkNow();
          expect(searches, 1);
          expect(handshakes, 1);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('search-trips-v2')) {
            searches++;
            return http.Response(
              jsonEncode({
                'data': {
                  'trains': [train.toJson()],
                },
              }),
              200,
            );
          }
          handshakes++;
          return http.Response(
            'Too many requests',
            429,
            headers: {'retry-after': '45'},
          );
        }),
      );
    },
  );

  test(
    'a busy server causes one booking attempt per cycle with backoff',
    () async {
      var searches = 0;
      var handshakes = 0;
      final before = monitor.nextCheckDelay();
      await http.runWithClient(
        () async {
          await monitor.checkNow();
          expect(searches, 1);
          expect(handshakes, 1);
          expect(monitor.isMonitoring, isTrue);
          expect(monitor.lastBookingError, isNotNull);
          expect(monitor.nextCheckDelay(), greaterThan(before));
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('search-trips-v2')) {
            searches++;
            return http.Response(
              jsonEncode({
                'data': {
                  'trains': [train.toJson()],
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('handshake')) handshakes++;
          return http.Response('{"message":"Server busy"}', 503);
        }),
      );
    },
  );

  test(
    'an unknown auto-book outcome keeps the record and stops duplicate booking',
    () async {
      var mutations = 0;
      await http.runWithClient(
        () async {
          await monitor.checkNow();
          expect(mutations, 1);
          expect((await BookingService.pending())?['status'], 'needsReview');
          expect(monitor.isMonitoring, isFalse);
          await monitor.checkNow();
          expect(mutations, 1);
        },
        () => MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('search-trips-v2')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'trains': [train.toJson()],
                },
              }),
              200,
            );
          }
          if (path.endsWith('handshake')) {
            return http.Response(
              '{"data":{"release_time_interval_in_minutes":300}}',
              200,
            );
          }
          if (path.endsWith('seat-layout')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'seatLayout': [
                    {
                      'floor_name': 'KA',
                      'seat_floor': 1,
                      'seat_fare': '400',
                      'layout': [
                        [
                          {
                            'seat_number': 'KA-1',
                            'ticket_id': 101,
                            'seat_availability': 1,
                          },
                        ],
                      ],
                    },
                  ],
                },
              }),
              200,
            );
          }
          mutations++;
          return http.Response('{}', 503);
        }),
      );
    },
  );

  test('sold-out monitoring never starts an automatic scan of every intermediate stop', () async {
    final paths = <String>[];
    await http.runWithClient(
      () async {
        await monitor.checkNow();
        expect(paths, hasLength(1));
        expect(paths.single, endsWith('search-trips-v2'));
      },
      () => MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          jsonEncode({
            'data': {
              'trains': [
                {...train.toJson(), 'seat_types': []},
              ],
            },
          }),
          200,
        );
      }),
    );
  });
}
