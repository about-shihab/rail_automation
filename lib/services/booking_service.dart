import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/auth_session.dart';
import '../models/seat_layout.dart';
import '../models/seat_type.dart';
import '../models/train_trip.dart';
import '../models/trip_record.dart';
import 'api_service.dart';
import 'app_config.dart';
import 'booking_activity.dart';
import 'app_update_service.dart';
import 'credit_service.dart';
import 'notification_service.dart';
import 'secure_store.dart';
import 'trip_history_service.dart';
import 'turnstile_gate.dart';
import '../utils/friendly_error.dart';

/// The layout already loaded for this booking; choosing seats must not fetch
/// it again and repeat the human check. Railway still validates reservations.
class BookingLayout {
  const BookingLayout._(
    this.tripId,
    this.routeId,
    this.sessionToken,
    this.layout,
  );

  final int tripId;
  final int routeId;
  final String sessionToken;
  final SeatLayoutResponse layout;
}

/// Existing official website contract, inspected 2026-09-27.
/// Never retries a mutation with an unknown outcome.
class BookingService {
  static const storageKey = 'rail_pending_reservation_v1';
  static const tripInfoUrl =
      'https://eticket.railway.gov.bd/booking/train/trip-info';
  static const reservationTimeoutMinutes = 5;

  static final _layoutRequests = <(int, int, String), Future<BookingLayout>>{};

  static Future<BookingLayout> loadLayout({
    required SeatType seat,
    required AuthSession auth,
    String label = '',
    bool allowPrompt = true,
  }) {
    final tripId = seat.tripId;
    final routeId = seat.tripRouteId;
    if (tripId == null || routeId == null) {
      return Future.error(StateError('Missing trip information.'));
    }
    final key = (tripId, routeId, auth.token);
    return _layoutRequests.putIfAbsent(
      key,
      () => BookingActivity.instance.run(BookingActivityStage.layout, () async {
        try {
          await AppUpdateService.instance.ensureBookingAllowed();
          return await TurnstileGate.instance.guardSeatLayout(
            label: label,
            allowPrompt: allowPrompt,
            run: (token) async => BookingLayout._(
              tripId,
              routeId,
              auth.token,
              await ApiService.fetchSeatLayout(
                tripId: tripId,
                tripRouteId: routeId,
                authSession: auth,
                cftResponse: token,
              ),
            ),
          );
        } finally {
          _layoutRequests.remove(key);
        }
      }),
    );
  }

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
        final id = map['id']?.toString() ?? '';
        await TripHistoryService().updateTripStatus(
          id,
          TripBookingStatus.expired,
          failureReason: 'Reservation timed out after 5 minutes',
        );
        await clear();
        return null;
      }

      // If OTP was sent and credit was not deducted yet, deduct 1 credit immediately
      if (map['credit_deducted'] != true &&
          (map['status'] == 'awaitingOtp' ||
              map['status'] == 'readyForPayment')) {
        map['credit_deducted'] = true;
        await save(map);
        final trainName =
            map['train']?['trip_number']?.toString() ??
            map['train']?['train_name']?.toString() ??
            'Train';
        final coach = (map['coach_names'] as String?)?.isNotEmpty == true
            ? (map['coach_names'] as String)
            : (map['coach']?['floor_name']?.toString() ??
                  map['coach']?['seat_floor']?.toString() ??
                  '');
        final seats =
            (map['seats'] as List?)
                ?.map((s) => s['seat_number']?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .join(', ') ??
            '';
        final seatInfo = coach.isNotEmpty ? '$coach ($seats)' : seats;
        await CreditService().deductBookingCredit(
          trainName: trainName,
          seatInfo: seatInfo,
        );
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
    return BookingActivity.instance.run(
      path.contains('otp')
          ? BookingActivityStage.verifying
          : BookingActivityStage.reserving,
      () async {
        if (!auth.isValid) {
          throw StateError('Login expired. Please sign in again.');
        }
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
          Duration(
            seconds: AppConfig.instance.number('request_timeout_seconds'),
          ),
        );
        final nextToken = response.headers['x-action-token'];
        if (nextToken != null) {
          await SecureStore.write('rail_action_token', nextToken);
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final friendly = friendlyErrorMessage(response.body);
          throw StateError(
            friendly.isNotEmpty
                ? friendly
                : 'Railway request failed with status ${response.statusCode}.',
          );
        }
        final json = jsonDecode(response.body);
        if (json is! Map || json['data'] is! Map) {
          throw const FormatException(
            'Unrecognized booking response. Check your reservation on the official site.',
          );
        }
        return Map<String, dynamic>.from(json['data']);
      },
    );
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
    bool isAutoBook = false,
    List<SeatItem>? selectedSeats,
    Future<bool> Function()? canReserve,
    BookingLayout? preparedLayout,
    bool allowVerificationPrompt = false,
  }) async {
    return BookingActivity.instance.run(
      BookingActivityStage.reserving,
      () async {
        await AppUpdateService.instance.ensureBookingAllowed();
        if (await pending() != null) {
          throw StateError(
            'An existing reservation needs your attention. Open it before starting another.',
          );
        }
        if (quantity < 1 || quantity > AppConfig.instance.number('max_seats')) {
          throw StateError('Invalid seat quantity.');
        }
        if (seat.tripId == null ||
            seat.tripRouteId == null ||
            train.boardingPoints.isEmpty) {
          throw StateError(
            'Trip or boarding information is missing. Open the official booking page.',
          );
        }
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
        final prepared =
            preparedLayout ??
            await loadLayout(
              seat: seat,
              auth: auth,
              label: '${train.tripNumber} · ${seat.type}',
              allowPrompt: allowVerificationPrompt,
            );
        if (prepared.tripId != seat.tripId ||
            prepared.routeId != seat.tripRouteId ||
            prepared.sessionToken != auth.token) {
          throw StateError(
            'Seat selection belongs to another booking. Reload seats.',
          );
        }
        final layout = prepared.layout;
        final candidates = <(CoachLayout, SeatItem)>[];
        for (final coach in layout.coaches) {
          final fare = double.tryParse(coach.seatFare);
          if (fare == null ||
              !fare.isFinite ||
              fare < 0 ||
              (maxFare != null && fare + seat.vatAmount > maxFare)) {
            continue;
          }
          for (final row in coach.layout) {
            for (final item in row) {
              if (item.isAvailable &&
                  item.ticketId > 0 &&
                  (selectedSeats == null ||
                      selectedSeats.any((s) => s.ticketId == item.ticketId))) {
                candidates.add((coach, item));
              }
            }
          }
        }
        final List<(CoachLayout, SeatItem)> chosen;
        if (selectedSeats != null && selectedSeats.isNotEmpty) {
          if (candidates.length < quantity) {
            throw StateError(
              'Selected seats are no longer available. Please select available seats.',
            );
          }
          chosen = candidates.take(quantity).toList();
        } else {
          candidates.shuffle(Random.secure());
          final coaches = candidates.map((c) => c.$1).toSet().toList()
            ..shuffle(Random.secure());
          final sameCoach = coaches
              .where(
                (c) =>
                    candidates.where((s) => identical(s.$1, c)).length >=
                    quantity,
              )
              .toList();
          if (sameCoach.isNotEmpty) {
            chosen = candidates
                .where((s) => identical(s.$1, sameCoach.first))
                .take(quantity)
                .toList();
          } else if (candidates.length >= quantity) {
            chosen = candidates.take(quantity).toList();
          } else {
            throw StateError(
              'Not enough matching seats remain. Monitoring can continue.',
            );
          }
        }
        final coachNames = chosen
            .map(
              (s) => s.$1.floorName.isNotEmpty
                  ? s.$1.floorName
                  : '${s.$1.seatFloor}',
            )
            .toSet()
            .join(', ');
        final state = <String, dynamic>{
          'id': AuthSession.generateUuid(),
          'status': 'reserving',
          'train': train.toJson(),
          'seatClass': seat.toJson(),
          'coach': chosen.first.$1.toJson(),
          'coach_names': coachNames,
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
              .add(
                Duration(
                  seconds: min(holdSeconds, reservationTimeoutMinutes * 60),
                ),
              )
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
            }, auth);
            if (data['ack'] != 1) {
              throw StateError('Seat reservation was not acknowledged.');
            }
            (state['confirmedTicketIds'] as List<int>).add(item.$2.ticketId);
            await save(state);
          }
          final data = await request(
            'POST',
            '/bookings/passenger-details',
            tripBody(state),
            auth,
          );
          if (data['success'] != true) {
            throw StateError(
              'Railway did not confirm the passenger-details step.',
            );
          }
          state['status'] = 'awaitingOtp';
          state['seniorCitizenEligible'] =
              data['senior_citizen_eligible'] == true;
          // Duration is captured from the official site's handshake, not invented locally.
          final seconds = int.tryParse(
            await SecureStore.read('rail_hold_seconds') ?? '',
          );
          if (seconds != null && seconds > 0) {
            state['expiresAt'] = DateTime.parse(state['startedAt'])
                .add(
                  Duration(
                    seconds: min(seconds, reservationTimeoutMinutes * 60),
                  ),
                )
                .toUtc()
                .toIso8601String();
          }
          final seatsList = chosen.map((s) => s.$2.seatNumber).toList();
          final coachName = coachNames.isNotEmpty
              ? coachNames
              : (chosen.first.$1.floorName.isNotEmpty
                    ? chosen.first.$1.floorName
                    : '${chosen.first.$1.seatFloor}');
          final fareNum =
              double.tryParse(chosen.first.$1.seatFare) ??
              (double.tryParse(seat.fare) ?? 0.0);

          // When OTP is sent, reservation costs 1 credit. User can proceed to pay with 0 credit.
          state['credit_deducted'] = true;
          if (isAutoBook || autoVerify) {
            state['isAutoBook'] = true;
          }
          await CreditService().deductBookingCredit(
            trainName: train.tripNumber,
            seatInfo: '$coachName (${seatsList.join(", ")})',
          );
          await save(state);

          try {
            await TripHistoryService().recordTrip(
              TripRecord(
                id: state['id']?.toString() ?? '',
                trainName: train.tripNumber,
                fromCity: from,
                toCity: to,
                dateOfJourney: date,
                seatClass: seat.type,
                seatNumbers: seatsList,
                coachName: coachName,
                totalFare:
                    fareNum *
                    (seatsList.isNotEmpty ? seatsList.length : quantity),
                status: TripBookingStatus.awaitingOtp,
                createdAt: DateTime.now(),
                isAutoBook: isAutoBook || autoVerify,
              ),
            );
          } catch (_) {}
          return state;
        } catch (_) {
          state['status'] = 'needsReview';
          await save(state);
          rethrow;
        }
      },
    );
  }

  static Future<Map<String, dynamic>>? _otpVerification;

  static Future<Map<String, dynamic>> verifyOtp(String otp, AuthSession auth) {
    final running = _otpVerification;
    if (running != null) return running;
    late final Future<Map<String, dynamic>> request;
    request = _verifyOtp(otp, auth).whenComplete(() {
      if (identical(_otpVerification, request)) _otpVerification = null;
    });
    _otpVerification = request;
    return request;
  }

  static Future<Map<String, dynamic>> _verifyOtp(
    String otp,
    AuthSession auth,
  ) async {
    final state = await pending();
    if (state == null || state['status'] != 'awaitingOtp') {
      throw StateError('No booking is awaiting OTP.');
    }
    final expires = DateTime.tryParse(state['expiresAt'] ?? '');
    if (expires != null && !DateTime.now().isBefore(expires)) {
      throw StateError('The reservation window has expired.');
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(otp)) {
      throw StateError('Enter a valid OTP.');
    }
    final data = await request('POST', '/bookings/verify-otp', {
      ...tripBody(state),
      'otp': otp,
    }, auth);
    if (data['success'] != true) {
      throw StateError('Railway did not verify this OTP.');
    }
    state['status'] = 'readyForPayment';
    state['otp'] = otp;
    await save(state);
    // OTP verified: Status is ready for payment.
    // Remember: Credit is NOT deducted on OTP verification, only on successful booking!
    return state;
  }

  /// Complete a successful booking:
  /// Deducts exactly 1 credit from DB via CreditService, updates status to successful
  /// in TripHistoryService, and clears the active reservation.
  static Future<bool> completeSuccessfulBooking({
    Map<String, dynamic>? reservation,
  }) async {
    final state = reservation ?? await pending();
    if (state == null) return false;

    final id = state['id']?.toString() ?? '';
    final trainName =
        state['train']?['trip_number']?.toString() ??
        state['train']?['train_name']?.toString() ??
        'Train';
    final coach = (state['coach_names'] as String?)?.isNotEmpty == true
        ? (state['coach_names'] as String)
        : (state['coach']?['floor_name']?.toString() ??
              state['coach']?['seat_floor']?.toString() ??
              '');
    final seats =
        (state['seats'] as List?)
            ?.map((s) => s['seat_number']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(', ') ??
        '';
    final seatInfo = coach.isNotEmpty ? '$coach ($seats)' : seats;

    // 1. Deduct exactly 1 credit for successful booking (if not already deducted at OTP send)
    if (state['credit_deducted'] != true) {
      await CreditService().deductBookingCredit(
        trainName: trainName,
        seatInfo: seatInfo,
      );
      state['credit_deducted'] = true;
    }

    // 2. Mark as SUCCESSFUL in trip history
    await TripHistoryService().updateTripStatus(
      id,
      TripBookingStatus.successful,
    );

    // 3. Clear active reservation and notifications
    await clear();

    // 4. Sequence Rule: Show clean ticket booked successfully notification
    try {
      await NotificationService().showPurchaseSuccessAlert(
        trainName: trainName,
        pnr: state['pnr']?.toString() ?? '',
      );
    } catch (_) {}

    return true;
  }

  static Future<void> resendOtp(AuthSession auth) async {
    final state = await pending();
    if (state == null || state['status'] != 'awaitingOtp') {
      throw StateError('No booking is awaiting OTP.');
    }
    final data = await request(
      'POST',
      '/bookings/resend-otp',
      tripBody(state),
      auth,
    );
    if (data['success'] != true) {
      throw StateError('Railway could not resend the OTP.');
    }
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
