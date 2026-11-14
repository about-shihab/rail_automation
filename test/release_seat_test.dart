import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/api_service.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/rail_api_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('RailApiConfig includes release_seat, bulk_release_seat and trips_past', () {
    expect(RailApiConfig.paths['release_seat'], '/bookings/release-seat');
    expect(RailApiConfig.paths['bulk_release_seat'], '/bookings/bulk-release-seat');
    expect(RailApiConfig.paths['trips_past'], '/trips/past-v2');
  });

  test('BookingService releaseSeat and bulkReleaseSeat methods exist', () {
    expect(BookingService.releaseSeat, isNotNull);
    expect(BookingService.bulkReleaseSeat, isNotNull);
    expect(BookingService.releasePendingHeldSeats, isNotNull);
    expect(ApiService.getPastTickets, isNotNull);
  });

  test('ApiService releaseSeat and bulkReleaseSeats send PATCH with ticket_id and route_id', () async {
    final session = AuthSession(
      token: 'real-shaped-test-session',
      deviceId: 'device',
      deviceKey: 'key',
    );

    final requests = <String>[];

    await http.runWithClient(() async {
      final singleOk = await ApiService.releaseSeat(
        ticketId: 860614101,
        routeId: 1234,
        authSession: session,
      );
      expect(singleOk, isTrue);

      final bulkOk = await ApiService.bulkReleaseSeats(
        ticketIds: [860614101],
        routeId: 1234,
        authSession: session,
      );
      expect(bulkOk, isTrue);
    }, () => MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/bookings/release-seat')) {
        expect(request.method, 'PATCH');
        final body = jsonDecode(request.body);
        expect(body['ticket_id'], 860614101);
        expect(body['route_id'], 1234);
        return http.Response(jsonEncode({'data': {'ack': 1}, 'success': true}), 200);
      }
      if (request.url.path.endsWith('/bookings/bulk-release-seat')) {
        expect(request.method, 'PATCH');
        final body = jsonDecode(request.body);
        expect(body['ticket_id'], 860614101);
        expect(body['route_id'], 1234);
        return http.Response(jsonEncode({'data': {'ack': 1}, 'success': true}), 200);
      }
      return http.Response('{}', 404);
    }));

    expect(requests.length, 2);
  });

  test('BookingService resetReserving clears reserving lock', () {
    BookingService.resetReserving();
    expect(BookingService.isReserving, isFalse);
  });
}
