import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rail_automation/models/auth_session.dart';
import 'package:rail_automation/services/booking_service.dart';
import 'package:rail_automation/services/rail_api_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthSession.save(
      AuthSession(
        token: 'test-token',
        deviceId: 'device-123',
        deviceKey: 'key-123',
        phoneNumber: '01700000000',
      ),
    );
  });

  test('RailApiConfig includes release_seat and bulk_release_seat endpoints', () {
    expect(RailApiConfig.paths['release_seat'], '/bookings/release-seat');
    expect(RailApiConfig.paths['bulk_release_seat'], '/bookings/bulk-release-seat');
  });

  test('BookingService.releaseSeat sends PATCH to /bookings/release-seat', () async {
    final calls = <http.Request>[];
    await http.runWithClient(
      () async {
        final auth = (await AuthSession.load())!;
        final success = await BookingService.releaseSeat(
          ticketId: 860614101,
          routeId: 1234,
          auth: auth,
        );
        expect(success, isTrue);
        expect(calls.length, 1);
        expect(calls.first.method, 'PATCH');
        expect(calls.first.url.path, endsWith('/bookings/release-seat'));
        final body = jsonDecode(calls.first.body);
        expect(body['ticket_id'], 860614101);
        expect(body['route_id'], 1234);
      },
      () => MockClient((req) async {
        calls.add(req);
        return http.Response(
          jsonEncode({
            'status': 200,
            'message': 'Seat released successfully',
            'data': {'ack': 1},
          }),
          200,
        );
      }),
    );
  });

  test('BookingService.bulkReleaseSeat sends PATCH to /bookings/bulk-release-seat', () async {
    final calls = <http.Request>[];
    await http.runWithClient(
      () async {
        final auth = (await AuthSession.load())!;
        final success = await BookingService.bulkReleaseSeat(
          ticketIds: [860614101, 860614102],
          routeId: 1234,
          auth: auth,
        );
        expect(success, isTrue);
        expect(calls.length, 1);
        expect(calls.first.method, 'PATCH');
        expect(calls.first.url.path, endsWith('/bookings/bulk-release-seat'));
        final body = jsonDecode(calls.first.body);
        expect(body['ticket_ids'], [860614101, 860614102]);
        expect(body['route_id'], 1234);
      },
      () => MockClient((req) async {
        calls.add(req);
        return http.Response(
          jsonEncode({
            'status': 200,
            'message': 'Seats released successfully',
            'data': {'ack': 1},
          }),
          200,
        );
      }),
    );
  });

  test('BookingService.releasePendingHeldSeats releases seats from active reservation', () async {
    final calls = <http.Request>[];
    await http.runWithClient(
      () async {
        await BookingService.save({
          'id': 'res-1',
          'status': 'awaitingOtp',
          'confirmedTicketIds': [860614101],
          'seatClass': {'trip_id': 100, 'trip_route_id': 1234},
          'seats': [{'ticket_id': 860614101, 'seat_number': 'JA-14'}],
        });

        final released = await BookingService.releasePendingHeldSeats();
        expect(released, isTrue);
        expect(calls.length, 1);
        expect(calls.first.url.path, endsWith('/bookings/bulk-release-seat'));
      },
      () => MockClient((req) async {
        calls.add(req);
        return http.Response(
          jsonEncode({
            'status': 200,
            'message': 'Seats released',
            'data': {'ack': 1},
          }),
          200,
        );
      }),
    );
  });
}

