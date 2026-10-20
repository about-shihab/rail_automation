import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';

import '../models/auth_session.dart';
import '../models/seat_type.dart';
import '../models/train_trip.dart';
import 'api_service.dart';
import 'journey_schedule.dart';
import 'rail_api_client.dart';

class IntermediateJourney {
  final String via, firstDate, secondDate;
  final TrainTrip first, second;
  final SeatType firstSeat, secondSeat;

  const IntermediateJourney({
    required this.via,
    required this.firstDate,
    required this.secondDate,
    required this.first,
    required this.second,
    required this.firstSeat,
    required this.secondSeat,
  });

  int get seats =>
      min(firstSeat.seatCounts.online, secondSeat.seatCounts.online);
}

/// A small alternative to a full station matrix: try one intermediate stop,
/// and require online seats in the same class on both legs of the same run.
class IntermediateStationSearch {
  static int? _minutes(String value) {
    for (final pattern in ['HH:mm', 'HH:mm:ss', 'hh:mm a', 'h:mm a']) {
      try {
        final time = DateFormat(
          pattern,
          'en_US',
        ).parseStrict(value.trim().toUpperCase());
        return time.hour * 60 + time.minute;
      } on FormatException {
        // Railway route times vary between 12-hour and 24-hour formats.
      }
    }
    return null;
  }

  static Future<List<IntermediateJourney>> search({
    required TrainTrip train,
    required String from,
    required String to,
    required String date,
    required AuthSession auth,
    String? seatClass,
    bool Function()? cancelled,
  }) async {
    final journeyDate = JourneySchedule.parseDate(date);
    if (journeyDate == null || train.trainModel.isEmpty) {
      throw StateError(
        'Train route information is unavailable. Try searching again.',
      );
    }
    final response = await RailApiClient.request(
      operation: 'train_routes',
      method: 'POST',
      payload: {
        'model': train.trainModel,
        'departure_date_time': DateFormat('yyyy-MM-dd').format(journeyDate),
      },
      auth: auth,
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Unable to load train stops (${response.statusCode}). Try again.',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = (decoded['data']?['routes'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    String city(int i) => '${routes[i]['city'] ?? ''}'.trim();
    final start = routes.indexWhere(
      (r) => '${r['city']}'.trim().toLowerCase() == from.trim().toLowerCase(),
    );
    final end = routes.indexWhere(
      (r) => '${r['city']}'.trim().toLowerCase() == to.trim().toLowerCase(),
    );
    if (start < 0 || end <= start) {
      throw StateError(
        'The selected stations were not found in this train route.',
      );
    }
    final tripIds = train.seatTypes
        .map((s) => s.tripId)
        .whereType<int>()
        .toSet();
    if (tripIds.isEmpty) {
      throw StateError('Train run information is unavailable.');
    }
    final requested = seatClass?.trim().toUpperCase();
    final anyClass =
        requested == null ||
        requested.isEmpty ||
        requested == 'ALL' ||
        requested == 'RANDOM';
    TrainTrip? sameRun(TripSearchResponse response) {
      for (final candidate in response.trains) {
        if (candidate.tripNumber == train.tripNumber &&
            candidate.seatTypes.any((s) => tripIds.contains(s.tripId))) {
          return candidate;
        }
      }
      return null;
    }

    final results = <IntermediateJourney>[];
    var day = 0;
    int? previous = _minutes('${routes[start]['departure_time'] ?? ''}');
    if (previous == null) {
      throw StateError(
        'Boarding time is unavailable. Cannot safely search this connection.',
      );
    }
    for (var i = start + 1; i < end; i++) {
      // Include arrival and departure to catch a stop spanning midnight.
      for (final field in ['arrival_time', 'departure_time']) {
        final time = _minutes('${routes[i][field] ?? ''}');
        if (time == null) continue;
        if (previous != null && time < previous) day++;
        previous = time;
      }
      if (cancelled?.call() == true) break;
      if (_minutes('${routes[i]['departure_time'] ?? ''}') == null ||
          previous == null) {
        throw StateError(
          'Departure time for ${city(i)} is unavailable. Cannot safely search this connection.',
        );
      }
      final secondDate = DateFormat(
        'dd-MMM-yyyy',
        'en_US',
      ).format(journeyDate.add(Duration(days: day)));
      final first = sameRun(
        await ApiService.searchTrips(
          fromCity: from,
          toCity: city(i),
          dateOfJourney: date,
          seatClass: seatClass,
          authSession: auth,
          silent: true,
        ),
      );
      if (cancelled?.call() == true) break;
      if (first == null ||
          !first.seatTypes.any(
            (s) =>
                s.isAvailable &&
                (anyClass || s.type.toUpperCase() == requested),
          )) {
        continue;
      }
      final second = sameRun(
        await ApiService.searchTrips(
          fromCity: city(i),
          toCity: to,
          dateOfJourney: secondDate,
          seatClass: seatClass,
          authSession: auth,
          silent: true,
        ),
      );
      if (second == null) continue;
      for (final seat in first.seatTypes) {
        if (!seat.isAvailable ||
            !tripIds.contains(seat.tripId) ||
            (!anyClass && seat.type.toUpperCase() != requested)) {
          continue;
        }
        final other = second.seatTypes
            .where(
              (s) =>
                  s.isAvailable &&
                  s.type == seat.type &&
                  s.tripId == seat.tripId,
            )
            .firstOrNull;
        if (other != null) {
          results.add(
            IntermediateJourney(
              via: city(i),
              firstDate: date,
              secondDate: secondDate,
              first: first,
              second: second,
              firstSeat: seat,
              secondSeat: other,
            ),
          );
        }
      }
    }
    return results;
  }
}
