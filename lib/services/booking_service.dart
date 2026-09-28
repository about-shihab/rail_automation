import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/auth_session.dart';
import '../models/seat_layout.dart';
import '../models/seat_type.dart';
import '../models/train_trip.dart';
import 'api_service.dart';
import 'app_config.dart';
import 'notification_service.dart';
import 'secure_store.dart';

/// Existing official website contract, inspected 2026-09-27.
/// Never retries a mutation with an unknown outcome.
class BookingService {
  static const storageKey = 'rail_pending_reservation_v1';
  static const tripInfoUrl =
      'https://eticket.railway.gov.bd/booking/train/trip-info';
  static const reservationTimeoutMinutes = 5;

  static Future<Map<String, dynamic>?> pending() async {
    final raw = await SecureStore.read(storageKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final started = DateTime.tryParse(map['startedAt'] ?? '');
      final expires = DateTime.tryParse(map['expiresAt'] ?? '');
      final now = DateTime.now();

      // Automatically clear after 5 minutes (300 seconds) from start or when expired
      final bool isExpiredByStartedAt =
          started != null &&
          now.difference(started).inSeconds >= (reservationTimeoutMinutes * 60);
      final bool isExpiredByExpiresAt =
          expires != null && !now.isBefore(expires);

      if (isExpiredByStartedAt || isExpiredByExpiresAt) {
        await clear();
        return null;
      }
      return map;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> save(Map<String, dynamic> value) {
    if (!value.containsKey('startedAt')) {
      value['startedAt'] = DateTime.now().toUtc().toIso8601String();
    }
    if (!value.containsKey('expiresAt')) {
      value['expiresAt'] = DateTime.now()
          .add(const Duration(minutes: reservationTimeoutMinutes))
          .toUtc()
          .toIso8601String();
    }
    return SecureStore.write(storageKey, jsonEncode(value));
  }

  static Future<void> clear() async {
    await SecureStore.delete(storageKey);
    try {
      await NotificationService().clearAlerts();
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> request(
    String method,
    String path,
    Map<String, dynamic> body,
    AuthSession auth,
  ) async {
    if (!auth.isValid) throw StateError('Login expired. Please sign in again.');
    final actionToken = await SecureStore.read('rail_action_token');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Origin': 'https://eticket.railway.gov.bd',
      'Referer': 'https://eticket.railway.gov.bd/',
      'Authorization': auth.token.startsWith('Bearer ')
          ? auth.token
          : 'Bearer ${auth.token}',
      'x-device-id': auth.deviceId,
      'x-device-key': auth.deviceKey,
      if (auth.cookie?.isNotEmpty == true) 'Cookie': auth.cookie!,
      'X-Action-Token': ?actionToken,
    };
    final uri = Uri.parse('${ApiService.baseUrl}$path');
    final future = method == 'PATCH'
        ? http.patch(uri, headers: headers, body: jsonEncode(body))
        : http.post(uri, headers: headers, body: jsonEncode(body));
    final response = await future.timeout(
      Duration(seconds: AppConfig.instance.number('request_timeout_seconds')),
    );
    final nextToken = response.headers['x-action-token'];
    if (nextToken != null)
      await SecureStore.write('rail_action_token', nextToken);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? serverMsg;
      try {
        final json = jsonDecode(response.body);
        if (json is Map) {
          serverMsg =
              json['message']?.toString() ??
              json['error']?.toString() ??
              json['detail']?.toString() ??
              json['msg']?.toString();
        }
      } catch (_) {
        if (response.body.isNotEmpty && response.body.length < 200) {
          serverMsg = response.body;
        }
      }
      final detail = (serverMsg != null && serverMsg.isNotEmpty)
          ? ': $serverMsg'
          : '';
      throw StateError(
        'Railway request $path failed (${response.statusCode})$detail',
      );
    }
    final json = jsonDecode(response.body);
    if (json is! Map || json['data'] is! Map)
      throw const FormatException(
        'Unrecognized booking response. Check your reservation on the official site.',
      );
    return Map<String, dynamic>.from(json['data']);
  }

  static Map<String, dynamic> tripBody(Map<String, dynamic> pending) => {
    'trip_id': pending['seatClass']['trip_id'],
    'trip_route_id': pending['seatClass']['trip_route_id'],
    'ticket_ids': (pending['seats'] as List)
        .map((s) => s['ticket_id'])
        .toList(),
  };

  static Future<Map<String, dynamic>> reserve({
    required TrainTrip train,
    required SeatType seat,
    required String from,
    required String to,
    required String date,
    required AuthSession auth,
    int quantity = 1,
    double? maxFare,
    bool autoVerify = false,
    List<SeatItem>? selectedSeats,
    Future<bool> Function()? canReserve,
    String? cftResponse,
  }) async {
    if (await pending() != null)
      throw StateError(
        'An existing reservation needs your attention. Open it before starting another.',
      );
    if (quantity < 1 || quantity > AppConfig.instance.number('max_seats'))
      throw StateError('Invalid seat quantity.');
    if (seat.tripId == null ||
        seat.tripRouteId == null ||
        train.boardingPoints.isEmpty)
      throw StateError(
        'Trip or boarding information is missing. Open the official booking page.',
      );
    final config = await request('POST', '/handshake', {
      'hash': null,
      'eticket': true,
      'shohoz': false,
      'trainBkash': false,
      'trainNagad': false,
    }, auth);
    final holdDuration = num.tryParse(
      '${config['release_time_interval_in_minutes']}',
    );
    if (holdDuration == null || holdDuration <= 0 || holdDuration > 3600) {
      throw StateError(
        'Railway reservation duration is unavailable. Please use the official booking page.',
      );
    }
    // The website rounds this server field to whole minutes after dividing by 60.
    final holdSeconds = (holdDuration / 60).ceil() * 60;
    await SecureStore.write('rail_hold_seconds', '$holdSeconds');
    final activeCft =
        cftResponse ??
        await SecureStore.read('rail_cft_token') ??
        await SecureStore.read('rail_action_token');
    final layout = await ApiService.fetchSeatLayout(
      tripId: seat.tripId!,
      tripRouteId: seat.tripRouteId!,
      authSession: auth,
      cftResponse: activeCft,
    );
    final candidates = <(CoachLayout, SeatItem)>[];
    for (final coach in layout.coaches) {
      final fare = double.tryParse(coach.seatFare);
      if (fare == null ||
          !fare.isFinite ||
          fare < 0 ||
          (maxFare != null && fare + seat.vatAmount > maxFare))
        continue;
      for (final row in coach.layout) {
        for (final item in row) {
          if (item.isAvailable &&
              item.ticketId > 0 &&
              (selectedSeats == null ||
                  selectedSeats.any((s) => s.ticketId == item.ticketId)))
            candidates.add((coach, item));
        }
      }
    }
    candidates.shuffle(Random.secure());
    // A single coach avoids mixing additional-coach surcharges and booking rules.
    final coaches = candidates.map((c) => c.$1).toSet().toList()
      ..shuffle(Random.secure());
    final eligible = coaches
        .where(
          (c) => candidates.where((s) => identical(s.$1, c)).length >= quantity,
        )
        .toList();
    if (eligible.isEmpty)
      throw StateError(
        'Not enough matching seats remain in one coach. Monitoring can continue.',
      );
    final chosen = candidates
        .where((s) => identical(s.$1, eligible.first))
        .take(quantity)
        .toList();
    final state = <String, dynamic>{
      'id': AuthSession.generateUuid(),
      'status': 'reserving',
      'train': train.toJson(),
      'seatClass': seat.toJson(),
      'coach': eligible.first.toJson(),
      'seats': chosen
          .map(
            (s) => {
              ...s.$2.toJson(),
              'floor': s.$1.seatFloor,
              'floor_name': s.$1.floorName,
              'fare': s.$1.seatFare,
              'selected_seat_class': seat.type,
            },
          )
          .toList(),
      'from': from,
      'to': to,
      'date': date,
      'confirmedTicketIds': <int>[],
      'autoVerify': autoVerify,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'expiresAt': DateTime.now()
          .add(Duration(seconds: min(holdSeconds, reservationTimeoutMinutes * 60)))
          .toUtc()
          .toIso8601String(),
    };
    if (canReserve != null && !await canReserve()) {
      throw StateError('This search has been paused or replaced.');
    }
    await save(
      state,
    ); // Persist before mutation, including unknown/timeout outcomes.
    try {
      for (final item in chosen) {
        final data = await request('PATCH', '/bookings/reserve-seat', {
          'ticket_id': item.$2.ticketId,
          'route_id': seat.tripRouteId,
          'extras': {
            'seat_number': item.$2.seatNumber,
            'trip_number': train.tripNumber,
            'origin_name': from,
            'destination_name': to,
          },
          if (activeCft != null && activeCft.isNotEmpty)
            'action_token': activeCft,
        }, auth);
        if (data['ack'] != 1)
          throw StateError('Seat reservation was not acknowledged.');
        (state['confirmedTicketIds'] as List<int>).add(item.$2.ticketId);
        await save(state);
      }
      final data = await request(
        'POST',
        '/bookings/passenger-details',
        tripBody(state),
        auth,
      );
      if (data['success'] != true)
        throw StateError('Railway did not confirm the passenger-details step.');
      state['status'] = 'awaitingOtp';
      state['seniorCitizenEligible'] = data['senior_citizen_eligible'] == true;
      // Duration is captured from the official site's handshake, not invented locally.
      final seconds = int.tryParse(
        await SecureStore.read('rail_hold_seconds') ?? '',
      );
      if (seconds != null && seconds > 0) {
        state['expiresAt'] = DateTime.parse(state['startedAt'])
            .add(Duration(seconds: min(seconds, reservationTimeoutMinutes * 60)))
            .toUtc()
            .toIso8601String();
      }
      await save(state);
      return state;
    } catch (_) {
      state['status'] = 'needsReview';
      await save(state);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(
    String otp,
    AuthSession auth,
  ) async {
    final state = await pending();
    if (state == null || state['status'] != 'awaitingOtp')
      throw StateError('No booking is awaiting OTP.');
    final expires = DateTime.tryParse(state['expiresAt'] ?? '');
    if (expires != null && !DateTime.now().isBefore(expires))
      throw StateError('The reservation window has expired.');
    if (!RegExp(r'^\d{4,8}$').hasMatch(otp))
      throw StateError('Enter a valid OTP.');
    final data = await request('POST', '/bookings/verify-otp', {
      ...tripBody(state),
      'otp': otp,
    }, auth);
    if (data['success'] != true)
      throw StateError('Railway did not verify this OTP.');
    state['status'] = 'readyForPayment';
    state['otp'] = otp;
    await save(state);
    return state;
  }

  static Future<void> resendOtp(AuthSession auth) async {
    final state = await pending();
    if (state == null || state['status'] != 'awaitingOtp')
      throw StateError('No booking is awaiting OTP.');
    final data = await request(
      'POST',
      '/bookings/resend-otp',
      tripBody(state),
      auth,
    );
    if (data['success'] != true)
      throw StateError('Railway could not resend the OTP.');
  }

  static Map<String, dynamic> webStorage(
    Map<String, dynamic> state,
    String phone,
  ) => {
    'initialPurchaseData$phone': jsonEncode({
      'selectedTrip': state['train'],
      'selectedSeatClass': state['seatClass'],
      'selectedCoach': state['coach'],
      'reservedSeats': _webReservedSeats(state),
      'selectedBoardingPoint': state['train']['boarding_points'][0],
      'searchInfo': {
        'fromStation': state['from'],
        'toStation': state['to'],
        'journeyDate': state['date'],
        'seatClass': state['seatClass']['type'],
      },
    }),
    if (state['expiresAt'] != null)
      'booking_continued_on':
          '${DateTime.parse(state['expiresAt']).millisecondsSinceEpoch}',
    'is_senior_citizen': '${state['seniorCitizenEligible'] == true}',
    if (state['status'] == 'readyForPayment')
      'continue_booking_otp_verified': '1',
    if (state['status'] == 'readyForPayment')
      'confirm_booking_otp': state['otp'],
  };

  static List<Map<String, dynamic>> _webReservedSeats(
    Map<String, dynamic> state,
  ) => (state['seats'] as List).map((raw) {
    final seat = Map<String, dynamic>.from(raw as Map);
    // Older reservations only stored the fare on the coach. The checkout
    // calculates ticket price and VAT using Number(reservedSeat.fare).
    final value = seat['fare'] ?? state['coach']['seat_fare'];
    final fare = num.tryParse('$value');
    if (fare == null || !fare.isFinite || fare < 0) {
      throw StateError(
        'Reservation fare is unavailable. Please reopen booking.',
      );
    }
    return {
      ...seat,
      'fare': fare,
      'selected_seat_class':
          seat['selected_seat_class'] ?? state['seatClass']['type'],
    };
  }).toList();
}
