import 'dart:convert';
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/train_trip.dart';
import 'package:rail_automation/services/intermediate_station_search.dart';
import 'package:rail_automation/services/rail_request_pacer.dart';

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
    TrainRouteCache.clear();
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
      cancel || firstSeats == 0 || selected == 'SNIGDHA' ? (cancel ? 0 : 2) : 3,
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

  test(
    'concurrent route loads share one request and reuse the successful cache',
    () async {
      var calls = 0;
      final response = Completer<http.Response>();
      Future<List<RouteStation>> load() =>
          IntermediateStationSearch.fetchTrainRouteStations(
            trainModel: '100',
            departureDate: '21-Oct-2026',
            auth: auth,
          );
      await http.runWithClient(
        () async {
          final first = load();
          final second = load();
          await Future<void>.delayed(Duration.zero);
          expect(calls, 1);
          response.complete(
            http.Response(
              jsonEncode({
                'data': {'routes': routes},
              }),
              200,
            ),
          );
          final results = await Future.wait([first, second]);
          expect(results.every((stops) => stops.length == 5), isTrue);
          expect(await load(), hasLength(5));
          expect(calls, 1);
        },
        () => MockClient((_) {
          calls++;
          return response.future;
        }),
      );
    },
  );

  test(
    'failed route load has no direct fallback and a later retry succeeds',
    () async {
      var calls = 0;
      await http.runWithClient(
        () async {
          Future<List<RouteStation>> load() =>
              IntermediateStationSearch.fetchTrainRouteStations(
                trainModel: '100',
                departureDate: '21-Oct-2026',
                auth: auth,
              );
          await expectLater(load(), throwsStateError);
          expect(calls, 1);
          expect(await load(), hasLength(5));
          expect(calls, 2);
        },
        () => MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('{}', 503)
              : http.Response(
                  jsonEncode({
                    'data': {'routes': routes},
                  }),
                  200,
                );
        }),
      );
    },
  );

  test('a route 429 is reported without an unpaced fallback', () async {
    var calls = 0;
    await http.runWithClient(
      () async {
        await expectLater(
          IntermediateStationSearch.fetchTrainRouteStations(
            trainModel: '100',
            departureDate: '21-Oct-2026',
            auth: auth,
          ),
          throwsA(isA<RailwayRateLimited>()),
        );
        expect(calls, 1);
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('Too many requests', 429);
      }),
    );
  });

  test('empty routes are not cached as a successful load', () async {
    var calls = 0;
    await http.runWithClient(
      () async {
        for (var i = 0; i < 2; i++) {
          await expectLater(
            IntermediateStationSearch.fetchTrainRouteStations(
              trainModel: '100',
              departureDate: '21-Oct-2026',
              auth: auth,
            ),
            throwsStateError,
          );
        }
        expect(calls, 2);
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('{"data":{"routes":[]}}', 200);
      }),
    );
  });

  final stations = [
    for (var i = 0; i < routes.length; i++) RouteStation.fromJson(routes[i], i),
  ];
  final target = TrainTrip.fromJson(train([seat('S_CHAIR', 1, 0)]));
  Future<StationPairAvailability> pair({String? seatClass}) =>
      IntermediateStationSearch.searchStationPair(
        from: stations[1],
        to: stations[3],
        date: '21-Oct-2026',
        targetTrain: target,
        auth: auth,
        seatClass: seatClass,
      );

  test(
    'station-pair network errors remain errors rather than sold-out results',
    () async {
      await http.runWithClient(
        () => expectLater(pair(), throwsException),
        () => MockClient((_) async => http.Response('{}', 503)),
      );
    },
  );

  test('station-pair results never substitute an unrelated train', () async {
    await http.runWithClient(
      () async {
        final result = await pair();
        expect(result.train, isNull);
        expect(result.hasSeats, isFalse);
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'trains': [
                {
                  'trip_number': 'OTHER (200)',
                  'train_model': '200',
                  'seat_types': [seat('S_CHAIR', 9, 6)],
                },
              ],
            },
          }),
          200,
        ),
      ),
    );
  });

  test('station-pair availability counts only the requested class', () async {
    await http.runWithClient(
      () async {
        final result = await pair(seatClass: 'S_CHAIR');
        expect(result.totalSeats, 2);
        expect(result.seatTypes.single.type, 'S_CHAIR');
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'trains': [
                train([seat('S_CHAIR', 1, 2), seat('SNIGDHA', 2, 10)]),
              ],
            },
          }),
          200,
        ),
      ),
    );
  });

  test(
    'station matching normalizes separators without matching partial names',
    () {
      final list = [
        RouteStation.fromJson({'city': 'Dhaka_Airport'}, 0),
        RouteStation.fromJson({'city': 'Dhaka'}, 1),
      ];
      expect(IntermediateStationSearch.findStationIndex(list, ' dhaka '), 1);
      expect(
        IntermediateStationSearch.findStationIndex(list, 'DHAKA  AIRPORT'),
        0,
      );
      expect(IntermediateStationSearch.findStationIndex(list, ''), -1);
    },
  );

  test(
    'segment boarding date follows midnight and the original boarding station',
    () {
      expect(
        IntermediateStationSearch.boardingDate(
          stations: stations,
          boarding: stations[2],
          referenceStation: 'From',
          date: '21-Oct-2026',
        ),
        '22-Oct-2026',
      );
      expect(
        IntermediateStationSearch.boardingDate(
          stations: stations,
          boarding: stations[1],
          referenceStation: 'Via',
          date: '22-Oct-2026',
        ),
        '21-Oct-2026',
      );
    },
  );
}
