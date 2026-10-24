import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/models/train_trip.dart';
import 'package:rail_automation/services/intermediate_station_search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TrainRouteCache.clear();
  });

  tearDown(() {
    TrainRouteCache.clear();
  });

  test('IntermediateJourney correctly identifies overlapping routes and leg bounds', () {
    final t1 = TrainTrip.fromJson({
      'trip_number': 'SUBORNO EXPRESS (701)',
      'departure_date_time': '07:00 AM',
      'arrival_date_time': '10:00 AM',
      'origin_city_name': 'Dhaka',
      'destination_city_name': 'Comilla',
      'train_model': '701',
      'seat_types': [
        {
          'key': 1,
          'type': 'SNIGDHA',
          'fare': '500',
          'seat_counts': {'online': 4, 'offline': 0, 'is_divided': false},
        },
      ],
    });
    final t2 = TrainTrip.fromJson({
      'trip_number': 'SUBORNO EXPRESS (701)',
      'departure_date_time': '09:00 AM',
      'arrival_date_time': '12:00 PM',
      'origin_city_name': 'Brahmanbaria',
      'destination_city_name': 'Chattogram',
      'train_model': '701',
      'seat_types': [
        {
          'key': 2,
          'type': 'SNIGDHA',
          'fare': '400',
          'seat_counts': {'online': 2, 'offline': 0, 'is_divided': false},
        },
      ],
    });

    // Overlapping journey (Dhaka -> Comilla and Brahmanbaria -> Chattogram)
    final journey = IntermediateJourney(
      via: 'Brahmanbaria & Comilla',
      viaCity: 'Brahmanbaria - Comilla',
      leg1ToStation: 'Comilla',
      leg2FromStation: 'Brahmanbaria',
      firstDate: '26-Oct-2026',
      secondDate: '26-Oct-2026',
      first: t1,
      second: t2,
      firstSeat: t1.seatTypes.first,
      secondSeat: t2.seatTypes.first,
    );

    expect(journey.isOverlapping, isTrue);
    expect(journey.leg1To, 'Comilla');
    expect(journey.leg2From, 'Brahmanbaria');
    expect(journey.seats, 2); // min(4, 2)
    expect(journey.layoverText(isBangla: false), contains('Same train'));
    expect(journey.layoverText(isBangla: false), contains('Brahmanbaria & Comilla'));
    expect(journey.layoverText(isBangla: true), contains('একই ট্রেন'));

    // Standard via journey (Dhaka -> Akhaura and Akhaura -> Chattogram)
    final standardVia = IntermediateJourney(
      via: 'Akhaura',
      viaCity: 'Akhaura',
      leg1ToStation: 'Akhaura',
      leg2FromStation: 'Akhaura',
      firstDate: '26-Oct-2026',
      secondDate: '26-Oct-2026',
      first: t1,
      second: t2,
      firstSeat: t1.seatTypes.first,
      secondSeat: t2.seatTypes.first,
    );

    expect(standardVia.isOverlapping, isFalse);
    expect(standardVia.leg1To, 'Akhaura');
    expect(standardVia.leg2From, 'Akhaura');
  });

  test('IntermediateStationSearch.search discovers overlapping route when includeOverlapping is true', () async {
    final auth = AuthSession(
      token: 'test-token',
      deviceId: 'device-1',
      deviceKey: 'test-key',
      phoneNumber: '01700000000',
    );

    // Stations: Dhaka (0) -> Airport (1) -> Brahmanbaria (2) -> Comilla (3) -> Chattogram (4)
    final routeStations = [
      {'city': 'Dhaka', 'arrival_time': '--:--', 'departure_time': '07:00 AM', 'halt_time': '0'},
      {'city': 'Airport', 'arrival_time': '07:25 AM', 'departure_time': '07:30 AM', 'halt_time': '5'},
      {'city': 'Brahmanbaria', 'arrival_time': '08:50 AM', 'departure_time': '08:55 AM', 'halt_time': '5'},
      {'city': 'Comilla', 'arrival_time': '10:00 AM', 'departure_time': '10:05 AM', 'halt_time': '5'},
      {'city': 'Chattogram', 'arrival_time': '12:30 PM', 'departure_time': '--:--', 'halt_time': '0'},
    ];
    TrainRouteCache.setRoute('701', '2026-10-26', routeStations);

    final baseTrain = TrainTrip.fromJson({
      'trip_number': 'SUBORNO EXPRESS (701)',
      'departure_date_time': '07:00 AM',
      'arrival_date_time': '12:30 PM',
      'origin_city_name': 'Dhaka',
      'destination_city_name': 'Chattogram',
      'train_model': '701',
      'seat_types': [
        {
          'key': 1,
          'type': 'SNIGDHA',
          'fare': '750',
          'seat_counts': {'online': 0, 'offline': 0, 'is_divided': false},
        },
      ],
    });

    // Mock API client:
    // Let's say:
    // Dhaka -> Comilla (station 3): 4 seats available
    // Brahmanbaria (station 2) -> Chattogram: 3 seats available
    // Other pairs have 0 seats.
    final mockClient = MockClient((request) async {
      final from = request.url.queryParameters['from_city'] ?? '';
      final to = request.url.queryParameters['to_city'] ?? '';

      int onlineSeats = 0;
      if (from == 'Dhaka' && to == 'Comilla') {
        onlineSeats = 4; // Leg 1: A -> C
      } else if (from == 'Brahmanbaria' && to == 'Chattogram') {
        onlineSeats = 3; // Leg 2: B -> E
      }

      return http.Response(
        jsonEncode({
          'data': {
            'trains': [
              {
                'trip_number': 'SUBORNO EXPRESS (701)',
                'train_model': '701',
                'departure_date_time': '07:00 AM',
                'arrival_date_time': '12:30 PM',
                'origin_city_name': from,
                'destination_city_name': to,
                'seat_types': [
                  {
                    'key': 1,
                    'type': 'SNIGDHA',
                    'fare': '500',
                    'seat_counts': {'online': onlineSeats, 'offline': 0, 'is_divided': false},
                  }
                ],
              }
            ]
          }
        }),
        200,
      );
    });

    await http.runWithClient(() async {
      // 1. When includeOverlapping is false (e.g. from Search Screen):
      // Should NOT return overlapping routes
      final standardResults = await IntermediateStationSearch.search(
        train: baseTrain,
        from: 'Dhaka',
        to: 'Chattogram',
        date: '26-Oct-2026',
        auth: auth,
        seatClass: 'SNIGDHA',
        includeOverlapping: false,
      );
      expect(standardResults.any((j) => j.isOverlapping), isFalse);

      // 2. When includeOverlapping is true (e.g. from Monitor Screen):
      // Should discover the overlapping route!
      final monitorResults = await IntermediateStationSearch.search(
        train: baseTrain,
        from: 'Dhaka',
        to: 'Chattogram',
        date: '26-Oct-2026',
        auth: auth,
        seatClass: 'SNIGDHA',
        includeOverlapping: true,
      );

      final overlap = monitorResults.firstWhere((j) => j.isOverlapping);
      expect(overlap, isNotNull);
      expect(overlap.leg1To, 'Comilla');
      expect(overlap.leg2From, 'Brahmanbaria');
      expect(overlap.seats, 3); // min(4, 3)
    }, () => mockClient);
  });
}
