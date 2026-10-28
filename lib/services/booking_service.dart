import 'dart:convert';
import 'dart:math';

import 'sms_service.dart';

import 'rail_api_client.dart';
import 'rail_api_config.dart';

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
import '../utils/railway_stations.dart';

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

  /// How long Railway holds a reserved seat. Configurable from the database
  /// (`reservation_timeout_minutes`, default 5).
  static int get reservationTimeoutMinutes =>
      AppConfig.instance.number('reservation_timeout_minutes');

  static final _layoutRequests = <(int, int, String), Future<BookingLayout>>{};
  static bool _reserving = false;

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
          await RailApiClient.ensureReady();
          var session = await RailApiClient.current(auth);
          if (!session.isValid) session = await RailApiClient.refresh(session);
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
                authSession: session,
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

      // Automatically clear after 5 minutes (300 seconds) from start or when expired.
      // Once OTP is verified (readyForPayment), only the payment expiration deadline (expiresAt) applies.
      final bool isReadyForPayment = map['status'] == 'readyForPayment';
      final bool isExpiredByStartedAt = !isReadyForPayment &&
          started != null &&
          now.difference(started).inSeconds >= (reservationTimeoutMinutes * 60);
      final bool isExpiredByExpiresAt =
          expires != null && !now.isBefore(expires);

      if (isExpiredByStartedAt || isExpiredByExpiresAt) {
        final id = map['id']?.toString() ?? '';
        await TripHistoryService().updateTripStatus(
          id,
          TripBookingStatus.expired,
          failureReason:
              'Reservation timed out after $reservationTimeoutMinutes minutes',
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
          .add(Duration(minutes: reservationTimeoutMinutes))
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
        final operation = RailApiConfig.paths.entries
            .firstWhere((entry) => entry.value == path)
            .key;
        final response = await RailApiClient.request(
          operation: operation,
          method: method,
          payload: body,
          auth: auth,
          headers: headers,
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
    if (_reserving) {
      throw StateError('A reservation is already in progress. Please wait.');
    }
    _reserving = true;
    try {
      return await BookingActivity.instance.run(
        BookingActivityStage.reserving,
        () async {
          await AppUpdateService.instance.ensureBookingAllowed();
          if (await pending() != null) {
            throw StateError(
              'An existing reservation needs your attention. Open it before starting another.',
            );
          }
          if (quantity < 1 ||
              quantity > AppConfig.instance.number('max_seats')) {
            throw StateError('Invalid seat quantity.');
          }
          if (seat.tripId == null || seat.tripRouteId == null) {
            throw StateError(
              'Trip information is missing. Open the official booking page.',
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
          if (holdDuration == null ||
              holdDuration <= 0 ||
              holdDuration > 3600) {
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
                        selectedSeats.any(
                          (s) => s.ticketId == item.ticketId,
                        ))) {
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
            'from': canonicalStation(from),
            'to': canonicalStation(to),
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
                  'origin_name': canonicalStation(from),
                  'destination_name': canonicalStation(to),
                },
              }, auth);
              if (data['ack'] != 1) {
                throw StateError('Seat reservation was not acknowledged.');
              }
              (state['confirmedTicketIds'] as List<int>).add(item.$2.ticketId);
              await save(state);
            }
            if (autoVerify && !await SmsService().prepareListening()) {
              state['autoVerify'] = false;
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
            BookingActivity.instance.clearWorkerStage();
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
            // Audio voice disabled per requirement; loud train whistle and vibration are used for alerts.

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
            // A timeout or rejection after some seats were held must retain the
            // booking record. Replaying an auto-book could reserve seats twice.
            state['status'] = 'needsReview';
            await save(state);
            rethrow;
          }
        },
      );
    } finally {
      _reserving = false;
    }
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
    // The website updates its logged-in user from the OTP response before
    // looking up initialPurchaseData<phone_number> on the payment page.
    final user = await checkoutUser(auth);
    final verifiedUser = data['user'];
    if (verifiedUser is Map) {
      if (verifiedUser['name'] != null) {
        user['display_name'] = verifiedUser['name'];
      }
      final mobile = verifiedUser['mobile'] ?? verifiedUser['phone_number'];
      if (mobile != null && '$mobile'.isNotEmpty) {
        user['phone_number'] = '$mobile';
      }
    }
    await SecureStore.write('rail_user', jsonEncode(user));
    state['status'] = 'readyForPayment';
    state['otp'] = otp;
    state['verifiedAt'] = DateTime.now().toUtc().toIso8601String();
    // Grant fresh 5-minute payment window after OTP verification
    state['expiresAt'] = DateTime.now()
        .add(Duration(minutes: reservationTimeoutMinutes))
        .toUtc()
        .toIso8601String();
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
    if (state['autoVerify'] == true && !await SmsService().prepareListening()) {
      state['autoVerify'] = false;
      await save(state);
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

  /// Checkout indexes the reservation by the user object's phone_number,
  /// rather than the native session's phone or the login payload's mobile.
  static Future<Map<String, dynamic>> checkoutUser(AuthSession auth) async {
    final raw = await SecureStore.read('rail_user');
    Map<String, dynamic> user = {};
    try {
      final decoded = jsonDecode(raw ?? '{}');
      if (decoded is Map) user = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final credentials = await AuthSession.getSavedUserCredentials();
    final candidates = [
      user['phone_number'],
      user['mobile_number'],
      user['mobile'],
      auth.phoneNumber,
      credentials['phone'],
    ];
    final phone = candidates
        .map((v) => v?.toString().trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (phone.isNotEmpty) {
      user['phone_number'] = phone;
      user['mobile_number'] = phone;
      user['mobile'] = phone;
    }
    if (user['display_name'] == null && auth.displayName != null) {
      user['display_name'] = auth.displayName;
    }
    if (user['email'] == null && auth.email != null) user['email'] = auth.email;
    return user;
  }

  static Map<String, dynamic> webStorage(
    Map<String, dynamic> state,
    String phone,
  ) {
    final rawSeats = _webReservedSeats(state);
    final train = state['train'] as Map<String, dynamic>?;
    final boardingPoints = train?['boarding_points'] as List?;
    final Map<String, dynamic> boardingPoint;
    if (boardingPoints != null && boardingPoints.isNotEmpty) {
      final first = Map<String, dynamic>.from(boardingPoints.first as Map);
      first['station_name'] = first['station_name'] ?? first['location_name'] ?? state['from'] ?? '';
      first['location_name'] = first['location_name'] ?? first['station_name'] ?? state['from'] ?? '';
      first['trip_id'] = first['trip_id'] ?? state['seatClass']?['trip_id'] ?? 0;
      first['trip_point_id'] = first['trip_point_id'] ?? 0;
      first['location_id'] = first['location_id'] ?? 0;
      first['location_time'] = first['location_time'] ?? state['date'] ?? '';
      first['location_date'] = first['location_date'] ?? state['date'] ?? '';
      boardingPoint = first;
    } else {
      boardingPoint = {
        'station_name': state['from'] ?? '',
        'location_name': state['from'] ?? '',
        'trip_id': state['seatClass']?['trip_id'] ?? 0,
        'trip_point_id': 0,
        'location_id': 0,
        'location_time': state['date'] ?? '',
        'location_date': state['date'] ?? '',
      };
    }

    final selectedTrip = {
      ...?train,
      'is_international': train?['is_international'] ?? false,
      'trip_number': train?['trip_number'] ?? '',
      'trip_id': state['seatClass']?['trip_id'] ?? 0,
      'boarding_points': boardingPoints ?? [boardingPoint],
    };

    final purchaseData = jsonEncode({
      'selectedTrip': selectedTrip,
      'selectedSeatClass': state['seatClass'],
      'selectedCoach': state['coach'],
      'reservedSeats': rawSeats,
      'selectedBoardingPoint': boardingPoint,
      'searchInfo': {
        'fromStation': state['from'],
        'toStation': state['to'],
        'journeyDate': state['date'],
        'seatClass': state['seatClass'] is Map
            ? (state['seatClass']['type'] ?? '')
            : '',
      },
    });

    final cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    final phone11 = cleanDigits.length >= 11
        ? cleanDigits.substring(cleanDigits.length - 11)
        : cleanDigits;
    final phone88 = phone11.isNotEmpty ? '88$phone11' : '';
    final phonePlus88 = phone11.isNotEmpty ? '+88$phone11' : '';

    final exp = state['expiresAt'] != null
        ? DateTime.tryParse('${state['expiresAt']}')?.millisecondsSinceEpoch
        : null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Always guarantee booking_continued_on is valid and in the future so Railway
    // PurchaseModule never trips "Booking time limit is exceeded!" redirect.
    final validExp = (exp != null && exp > nowMs + 60000)
        ? exp
        : nowMs + (reservationTimeoutMinutes * 60 * 1000);

    return {
      'initialPurchaseData$phone': purchaseData,
      if (phone11.isNotEmpty && phone11 != phone)
        'initialPurchaseData$phone11': purchaseData,
      if (phone88.isNotEmpty && phone88 != phone)
        'initialPurchaseData$phone88': purchaseData,
      if (phonePlus88.isNotEmpty && phonePlus88 != phone)
        'initialPurchaseData$phonePlus88': purchaseData,
      'initialPurchaseData': purchaseData,
      'initialPurchaseDataundefined': purchaseData,
      'initialPurchaseDatanull': purchaseData,
      'booking_continued_on': '$validExp',
      'is_senior_citizen': '${state['seniorCitizenEligible'] == true}',
      if (state['status'] == 'readyForPayment')
        'continue_booking_otp_verified': '1',
      if (state['status'] == 'readyForPayment')
        'confirm_booking_otp': state['otp'] ?? '',
    };
  }

  static List<Map<String, dynamic>> _webReservedSeats(
    Map<String, dynamic> state,
  ) => (state['seats'] as List).map((raw) {
    final seat = Map<String, dynamic>.from(raw as Map);
    // Older reservations only stored the fare on the coach. The checkout
    // calculates ticket price and VAT using Number(reservedSeat.fare).
    final value = seat['fare'] ?? state['coach']?['seat_fare'];
    final fare = num.tryParse('$value');
    if (fare == null || !fare.isFinite || fare < 0) {
      throw StateError(
        'Reservation fare is unavailable. Please reopen booking.',
      );
    }
    final vatAmount = seat['vat_amount'] ?? state['seatClass']?['vat_amount'] ?? 0;
    return {
      ...seat,
      'fare': fare,
      'vat_amount': vatAmount,
      'selected_seat_class':
          seat['selected_seat_class'] ?? state['seatClass']?['type'] ?? '',
    };
  }).toList();
}
