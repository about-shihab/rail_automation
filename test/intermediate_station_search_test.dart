import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/train_trip.dart';
import 'package:rail_automation/services/intermediate_station_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthSession(token: 'test-token', deviceKey: 'key');
  Map<String, dynamic> seat(String type, int id, int count) => {
    'type': type,
    'trip_id': id,
    'trip_route_id': 100 + count,
    'fare': '200',
    'seat_counts': {'online': count, 'offline': 20},
  };
  Map<String, dynamic> train(List<Map<String, dynamic>> seats) => {
    'trip_number': 'TEST (100)',
    'train_model': '100',
    'seat_types': seats,
  };
  final routes = [
    {'city': 'Before', 'departure_time': '21:00'},
    {'city': 'From', 'arrival_time': '22:00', 'departure_time': '23:00'},
    {'city': 'Via', 'arrival_time': '23:58', 'departure_time': '00:05'},
    {'city': 'To', 'arrival_time': '02:00'},
    {'city': 'After', 'departure_time': '03:00'},
  ];
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<List<IntermediateJourney>> run({
    int secondId = 1,
    int firstSeats = 4,
    int secondSeats = 2,
    String? selected,
    bool routeError = false,
    bool cancel = false,
    List<Map<String, dynamic>>? stops,
  }) async {
    final calls = <http.Request>[];
    final results = await http.runWithClient(
      () => IntermediateStationSearch.search(
        train: TrainTrip.fromJson(
          train([seat('S_CHAIR', 1, 0), seat('SNIGDHA', 2, 0)]),
        ),
        from: 'From',
        to: 'To',
        date: '21-Oct-2026',
        auth: auth,
        seatClass: selected,
        cancelled: () => cancel,
      ),
      () => MockClient((request) async {
        calls.add(request);
        if (request.url.path.endsWith('/train-routes')) {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body)['model'], '100');
          return http.Response(
            jsonEncode({
              'data': {'routes': stops ?? routes},
            }),
            routeError ? 500 : 200,
          );
        }
        final query = request.url.queryParameters;
        final first = query['from_city'] == 'From';
        expect(query['from_city'], first ? 'From' : 'Via');
        expect(query['to_city'], first ? 'Via' : 'To');
        expect(query['date_of_journey'], first ? '21-Oct-2026' : '22-Oct-2026');
        return http.Response(
          jsonEncode({
            'data': {
              'trains': [
                train([
                  seat(
                    'S_CHAIR',
                    first ? 1 : secondId,
                    first ? firstSeats : secondSeats,
                  ),
                ]),
              ],
            },
          }),
          200,
        );
      }),
    );
    expect(
      calls.length,
      cancel || firstSeats == 0 || selected == 'SNIGDHA' ? (cancel ? 1 : 2) : 3,
    );
    return results;
  }

  test(
    'finds two legs of same run, skips outside stops and crosses midnight',
    () async {
      final results = await run();
      expect(results.single.via, 'Via');
      expect(results.single.seats, 2);
      expect(results.single.secondDate, '22-Oct-2026');
      expect(
        results.single.firstSeat.tripRouteId,
        isNot(results.single.secondSeat.tripRouteId),
      );
    },
  );
  test('rejects another run with the same train name', () async {
    expect(await run(secondId: 99), isEmpty);
  });
  test('offline seats cannot complete a journey', () async {
    expect(await run(secondSeats: 0), isEmpty);
  });
  test('does not query second leg when first is sold out', () async {
    expect(await run(firstSeats: 0), isEmpty);
  });
  test('honors selected class', () async {
    expect(await run(selected: 'SNIGDHA'), isEmpty);
  });
  test('route failure is an error, not a no-seat result', () async {
    await expectLater(run(routeError: true), throwsStateError);
  });
  test('stops searching after leaving screen', () async {
    expect(await run(cancel: true), isEmpty);
  });
  test('missing boarding time fails instead of guessing a date', () async {
    await expectLater(
      run(
        stops: [
          {'city': 'From'},
          routes[2],
          routes[3],
        ],
      ),
      throwsStateError,
    );
  });
}
