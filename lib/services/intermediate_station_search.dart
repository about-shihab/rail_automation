import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/auth_session.dart';
import '../models/seat_type.dart';
import '../models/train_trip.dart';
import 'api_service.dart';
import 'journey_schedule.dart';
import 'rail_api_client.dart';
import 'rail_api_config.dart';

/// Legacy model for backwards compatibility with tests and views.
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

/// Represents a station along a train's scheduled route.
class RouteStation {
  final String city;
  final String name;
  final String arrivalTime;
  final String departureTime;
  final String haltTime;
  final int sequence;

  const RouteStation({
    required this.city,
    required this.name,
    required this.arrivalTime,
    required this.departureTime,
    required this.haltTime,
    required this.sequence,
  });

  factory RouteStation.fromJson(Map<String, dynamic> json, int index) {
    final rawCity = '${json['city'] ?? ''}'.trim();
    final clean = rawCity.replaceAll('_', ' ').trim();
    return RouteStation(
      city: rawCity,
      name: clean.isEmpty ? 'Station ${index + 1}' : clean,
      arrivalTime: IntermediateStationSearch.cleanTime('${json['arrival_time'] ?? ''}'),
      departureTime: IntermediateStationSearch.cleanTime('${json['departure_time'] ?? ''}'),
      haltTime: '${json['halt_time'] ?? ''}'.trim(),
      sequence: index,
    );
  }
}

/// Result of checking live seat availability between two stations on a train.
class StationPairAvailability {
  final RouteStation from;
  final RouteStation to;
  final TrainTrip? train;
  final bool hasSeats;
  final int totalSeats;
  final List<SeatType> seatTypes;

  const StationPairAvailability({
    required this.from,
    required this.to,
    required this.train,
    required this.hasSeats,
    required this.totalSeats,
    required this.seatTypes,
  });
}

/// Robust intermediate station and railway route matrix search.
/// Inspired by RailwayMatrixBD: discovers seats between in-between stations
/// when direct seats for the journey are unavailable.
class IntermediateStationSearch {
  /// Extracts the numeric model code from a TrainTrip (e.g. "701" from "SUBORNO EXPRESS (701)").
  static String extractTrainModel(TrainTrip train) {
    if (train.trainModel.trim().isNotEmpty && train.trainModel.trim() != 'null') {
      return train.trainModel.trim();
    }
    final match = RegExp(r'\((\d+)\)').firstMatch(train.tripNumber);
    if (match != null) return match.group(1)!;
    final digits = RegExp(r'\d+').firstMatch(train.tripNumber);
    return digits?.group(0) ?? '';
  }

  /// Cleans time strings returned by Shohoz API (e.g. "07:00 am BST" -> "07:00 AM").
  static String cleanTime(String raw) {
    if (raw.trim().isEmpty || raw.trim() == '--:--') return '';
    return raw
        .replaceAll(RegExp(r'\b(BST|BDT|UTC|GMT)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Parses minutes safely without throwing exceptions on unknown time zones.
  static int? parseMinutes(String raw) {
    final cleaned = cleanTime(raw);
    if (cleaned.isEmpty) return null;
    for (final pattern in ['HH:mm', 'HH:mm:ss', 'hh:mm a', 'h:mm a']) {
      try {
        final time = DateFormat(pattern, 'en_US').parseStrict(cleaned.toUpperCase());
        return time.hour * 60 + time.minute;
      } on FormatException {
        // try next
      }
    }
    return null;
  }

  /// Loads all stations along the train route using the official train-routes API.
  static Future<List<RouteStation>> fetchTrainRouteStations({
    required String trainModel,
    required String departureDate,
    AuthSession? auth,
  }) async {
    final journeyDate = JourneySchedule.parseDate(departureDate) ?? DateTime.now();
    final dateParam = DateFormat('yyyy-MM-dd').format(journeyDate);

    Map<String, dynamic>? decoded;

    if (auth != null && auth.isValid) {
      try {
        final response = await RailApiClient.request(
          operation: 'train_routes',
          method: 'POST',
          payload: {
            'model': trainModel,
            'departure_date_time': dateParam,
          },
          auth: auth,
        );
        if (response.statusCode == 200) {
          decoded = jsonDecode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        // Fallback to direct public request
      }
    }

    if (decoded == null) {
      final url = Uri.parse('${RailApiConfig.baseUrl}/train-routes');
      final response = await http.post(
        url,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Origin': 'https://eticket.railway.gov.bd',
          'Referer': 'https://eticket.railway.gov.bd/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
        },
        body: jsonEncode({
          'model': trainModel,
          'departure_date_time': dateParam,
        }),
      );
      if (response.statusCode != 200) {
        throw StateError(
          'Could not load train route information (${response.statusCode}).',
        );
      }
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    }

    final rawRoutes = (decoded['data']?['routes'] as List? ?? []);
    final stations = <RouteStation>[];
    for (var i = 0; i < rawRoutes.length; i++) {
      stations.add(RouteStation.fromJson(
        Map<String, dynamic>.from(rawRoutes[i] as Map),
        i,
      ));
    }
    return stations;
  }

  /// Matches user-entered city against station list flexibly (with underscores or spaces).
  static int findStationIndex(List<RouteStation> stations, String query) {
    final normalized = query.trim().replaceAll(' ', '_').toLowerCase();
    for (var i = 0; i < stations.length; i++) {
      final cityNorm = stations[i].city.trim().replaceAll(' ', '_').toLowerCase();
      final nameNorm = stations[i].name.trim().replaceAll(' ', '_').toLowerCase();
      if (cityNorm == normalized || nameNorm == normalized) return i;
      if (cityNorm.contains(normalized) || normalized.contains(cityNorm)) return i;
    }
    return -1;
  }

  /// Searches for split journey options (From -> Via -> To) where tickets are available
  /// on both legs of this train route.
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
    final model = extractTrainModel(train);
    if (journeyDate == null || model.isEmpty) {
      throw StateError(
        'Train route information is unavailable. Try searching again.',
      );
    }

    final dateParam = DateFormat('yyyy-MM-dd').format(journeyDate);
    final response = await RailApiClient.request(
      operation: 'train_routes',
      method: 'POST',
      payload: {
        'model': model,
        'departure_date_time': dateParam,
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
      (r) => '${r['city']}'.trim().replaceAll(' ', '_').toLowerCase() ==
          from.trim().replaceAll(' ', '_').toLowerCase(),
    );
    final end = routes.indexWhere(
      (r) => '${r['city']}'.trim().replaceAll(' ', '_').toLowerCase() ==
          to.trim().replaceAll(' ', '_').toLowerCase(),
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

    final requested = seatClass?.trim().toUpperCase();
    final anyClass =
        requested == null ||
        requested.isEmpty ||
        requested == 'ALL' ||
        requested == 'RANDOM';

    TrainTrip? sameRun(TripSearchResponse response) {
      for (final candidate in response.trains) {
        if (candidate.tripNumber == train.tripNumber &&
            (tripIds.isEmpty ||
                candidate.seatTypes.any((s) => tripIds.contains(s.tripId)))) {
          return candidate;
        }
      }
      return null;
    }

    final results = <IntermediateJourney>[];
    var day = 0;
    int? previous = parseMinutes('${routes[start]['departure_time'] ?? ''}');
    if (previous == null) {
      throw StateError(
        'Boarding time is unavailable. Cannot safely search this connection.',
      );
    }

    for (var i = start + 1; i < end; i++) {
      for (final field in ['arrival_time', 'departure_time']) {
        final time = parseMinutes('${routes[i][field] ?? ''}');
        if (time == null) continue;
        if (previous != null && time < previous) day++;
        previous = time;
      }
      if (cancelled?.call() == true) break;
      if (parseMinutes('${routes[i]['departure_time'] ?? ''}') == null ||
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
            (tripIds.isNotEmpty && !tripIds.contains(seat.tripId)) ||
            (!anyClass && seat.type.toUpperCase() != requested)) {
          continue;
        }
        final other = second.seatTypes
            .where(
              (s) =>
                  s.isAvailable &&
                  s.type == seat.type &&
                  (tripIds.isEmpty || s.tripId == seat.tripId),
            )
            .firstOrNull;
        if (other != null) {
          results.add(
            IntermediateJourney(
              via: city(i).replaceAll('_', ' '),
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

  /// Searches live availability between any specific pair of stations on this train.
  static Future<StationPairAvailability> searchStationPair({
    required RouteStation from,
    required RouteStation to,
    required String date,
    required TrainTrip targetTrain,
    required AuthSession auth,
    String? seatClass,
  }) async {
    try {
      final res = await ApiService.searchTrips(
        fromCity: from.city,
        toCity: to.city,
        dateOfJourney: date,
        seatClass: seatClass,
        authSession: auth,
        silent: true,
      );
      final targetClean = targetTrain.tripNumber.replaceAll(RegExp(r'\s+'), '').toLowerCase();
      final targetModel = extractTrainModel(targetTrain);

      TrainTrip? matched;
      for (final c in res.trains) {
        if (c.tripNumber.replaceAll(RegExp(r'\s+'), '').toLowerCase() == targetClean) {
          matched = c;
          break;
        }
        if (targetModel.isNotEmpty && extractTrainModel(c) == targetModel) {
          matched = c;
          break;
        }
      }
      matched ??= res.trains.isNotEmpty ? res.trains.first : null;

      final available = matched?.availableSeatTypes ?? [];
      final count = matched?.totalOnlineSeats ?? 0;
      return StationPairAvailability(
        from: from,
        to: to,
        train: matched,
        hasSeats: count > 0,
        totalSeats: count,
        seatTypes: available,
      );
    } catch (_) {
      return StationPairAvailability(
        from: from,
        to: to,
        train: null,
        hasSeats: false,
        totalSeats: 0,
        seatTypes: [],
      );
    }
  }
}
