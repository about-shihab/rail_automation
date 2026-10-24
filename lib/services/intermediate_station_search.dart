import 'dart:convert';
import 'dart:math';

import 'package:intl/intl.dart';

import '../models/auth_session.dart';
import '../models/seat_type.dart';
import '../models/train_trip.dart';
import '../utils/railway_stations.dart';
import 'api_service.dart';
import 'journey_schedule.dart';
import 'rail_api_client.dart';

/// Legacy model for backwards compatibility with tests and views.
class IntermediateJourney {
  final String via, firstDate, secondDate;
  final String viaCity;
  final TrainTrip first, second;
  final SeatType firstSeat, secondSeat;
  final String? leg1ToStation;
  final String? leg2FromStation;

  const IntermediateJourney({
    required this.via,
    this.viaCity = '',
    required this.firstDate,
    required this.secondDate,
    required this.first,
    required this.second,
    required this.firstSeat,
    required this.secondSeat,
    this.leg1ToStation,
    this.leg2FromStation,
  });

  String get leg1To =>
      leg1ToStation != null && leg1ToStation!.isNotEmpty
          ? leg1ToStation!
          : (viaCity.isNotEmpty ? viaCity : via);

  String get leg2From =>
      leg2FromStation != null && leg2FromStation!.isNotEmpty
          ? leg2FromStation!
          : (viaCity.isNotEmpty ? viaCity : via);

  bool get isOverlapping =>
      canonicalStation(leg1To) != canonicalStation(leg2From);

  String get canonicalVia =>
      viaCity.isNotEmpty ? viaCity : canonicalStation(via);

  int get seats =>
      min(firstSeat.seatCounts.online, secondSeat.seatCounts.online);

  int? get layoverMinutes {
    if (isOverlapping) return 0;
    final arr = IntermediateStationSearch.parseMinutes(first.arrivalDateTime);
    final dep = IntermediateStationSearch.parseMinutes(
      second.departureDateTime,
    );
    if (arr != null && dep != null) {
      var diff = dep - arr;
      if (diff < 0) diff += 24 * 60;
      return diff;
    }
    return null;
  }

  String layoverText({required bool isBangla}) {
    if (isOverlapping) {
      return isBangla
          ? 'একই ট্রেন: $leg2From ও $leg1To এর মধ্যে আসন পরিবর্তন'
          : 'Same train: change seats between $leg2From & $leg1To';
    }
    final mins = layoverMinutes;
    if (mins == null) {
      return isBangla ? '$via-এ যাত্রাবিরতি' : 'Transfer at $via';
    }
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return isBangla
          ? '$via-এ $h ঘণ্টা ${m > 0 ? "$m মি. " : ""}যাত্রাবিরতি'
          : '$h hr ${m > 0 ? "$m min " : ""}layover at $via';
    }
    return isBangla
        ? '$via-এ $mins মিনিট যাত্রাবিরতি'
        : '$mins min layover at $via';
  }
}

/// Seat availability and pricing for a specific seat class across both legs of a via route.
class ViaClassOption {
  final String type;
  final String displayName;
  final int leg1Seats;
  final int leg2Seats;
  final int minSeats;
  final double totalFare;
  final SeatType firstSeat;
  final SeatType secondSeat;

  const ViaClassOption({
    required this.type,
    required this.displayName,
    required this.leg1Seats,
    required this.leg2Seats,
    required this.minSeats,
    required this.totalFare,
    required this.firstSeat,
    required this.secondSeat,
  });
}

/// Unified via split route grouped by intermediate station.
/// Cleanly presents seat availability categorized by seat type (not bogi numbers).
class ViaRouteGroup {
  final String via;
  final String viaCity;
  final TrainTrip first;
  final TrainTrip second;
  final String firstDate;
  final String secondDate;
  final List<ViaClassOption> classOptions;

  const ViaRouteGroup({
    required this.via,
    this.viaCity = '',
    required this.first,
    required this.second,
    required this.firstDate,
    required this.secondDate,
    required this.classOptions,
  });

  String get canonicalVia =>
      viaCity.isNotEmpty ? viaCity : canonicalStation(via);

  int get maxAvailableSeats => classOptions.fold<int>(
    0,
    (maxVal, opt) => opt.minSeats > maxVal ? opt.minSeats : maxVal,
  );

  int? get layoverMinutes {
    final arr = IntermediateStationSearch.parseMinutes(first.arrivalDateTime);
    final dep = IntermediateStationSearch.parseMinutes(
      second.departureDateTime,
    );
    if (arr != null && dep != null) {
      var diff = dep - arr;
      if (diff < 0) diff += 24 * 60;
      return diff;
    }
    return null;
  }

  String layoverText({required bool isBangla}) {
    final mins = layoverMinutes;
    if (mins == null) {
      return isBangla ? '$via-এ যাত্রাবিরতি' : 'Transfer at $via';
    }
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return isBangla
          ? '$via-এ $h ঘণ্টা ${m > 0 ? "$m মি. " : ""}যাত্রাবিরতি'
          : '$h hr ${m > 0 ? "$m min " : ""}layover at $via';
    }
    return isBangla
        ? '$via-এ $mins মিনিট যাত্রাবিরতি'
        : '$mins min layover at $via';
  }

  static List<ViaRouteGroup> fromJourneys(List<IntermediateJourney> journeys) {
    final Map<String, List<IntermediateJourney>> byVia = {};
    for (final j in journeys) {
      byVia.putIfAbsent(j.via, () => []).add(j);
    }

    final groups = <ViaRouteGroup>[];
    for (final entry in byVia.entries) {
      final via = entry.key;
      final list = entry.value;
      if (list.isEmpty) continue;

      final firstJourney = list.first;
      final classOptions = <ViaClassOption>[];
      final seenTypes = <String>{};

      for (final j in list) {
        if (seenTypes.contains(j.firstSeat.type)) continue;
        seenTypes.add(j.firstSeat.type);

        final fare1 = double.tryParse(j.firstSeat.fare) ?? 0;
        final fare2 = double.tryParse(j.secondSeat.fare) ?? 0;

        classOptions.add(
          ViaClassOption(
            type: j.firstSeat.type,
            displayName: j.firstSeat.displayName,
            leg1Seats: j.firstSeat.seatCounts.online,
            leg2Seats: j.secondSeat.seatCounts.online,
            minSeats: j.seats,
            totalFare: fare1 + fare2,
            firstSeat: j.firstSeat,
            secondSeat: j.secondSeat,
          ),
        );
      }

      groups.add(
        ViaRouteGroup(
          via: via,
          viaCity: firstJourney.canonicalVia,
          first: firstJourney.first,
          second: firstJourney.second,
          firstDate: firstJourney.firstDate,
          secondDate: firstJourney.secondDate,
          classOptions: classOptions,
        ),
      );
    }
    return groups;
  }
}

/// In-memory cache for train routes and sliced intermediate stations.
/// Once a train's route stops are loaded for a date, subsequent monitor cycles
/// and searches re-use them directly without repeated POST /train-routes calls.
class TrainRouteCache {
  static final Map<String, List<Map<String, dynamic>>> _routes = {};
  static final Map<String, List<String>> _intermediate = {};
  static final Map<String, List<Map<String, dynamic>>> _stoppagesByModel = {};

  static String _routeKey(String model, String date) =>
      '${model.trim().toLowerCase()}_${date.trim().toLowerCase()}';

  static String _interKey(String train, String from, String to) =>
      '${train.trim().toLowerCase()}_${from.trim().toLowerCase()}_${to.trim().toLowerCase()}';

  static List<Map<String, dynamic>>? getRoute(String model, String date) {
    final byDate = _routes[_routeKey(model, date)];
    if (byDate != null) return byDate;
    return _stoppagesByModel[model.trim().toLowerCase()];
  }

  static void setRoute(
    String model,
    String date,
    List<Map<String, dynamic>> routes,
  ) {
    _routes[_routeKey(model, date)] = routes;
    _stoppagesByModel[model.trim().toLowerCase()] = routes;
  }

  static List<String>? getIntermediate(String train, String from, String to) =>
      _intermediate[_interKey(train, from, to)];

  static void setIntermediate(
    String train,
    String from,
    String to,
    List<String> stops,
  ) {
    _intermediate[_interKey(train, from, to)] = stops;
  }

  static void clear() {
    _routes.clear();
    _intermediate.clear();
    _stoppagesByModel.clear();
  }
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
      arrivalTime: IntermediateStationSearch.cleanTime(
        '${json['arrival_time'] ?? ''}',
      ),
      departureTime: IntermediateStationSearch.cleanTime(
        '${json['departure_time'] ?? ''}',
      ),
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
  final String date;

  const StationPairAvailability({
    required this.from,
    required this.to,
    required this.train,
    required this.hasSeats,
    required this.totalSeats,
    required this.seatTypes,
    required this.date,
  });
}

/// Robust intermediate station and railway route matrix search.
/// Inspired by RailwayMatrixBD: discovers seats between in-between stations
/// when direct seats for the journey are unavailable.
class IntermediateStationSearch {
  /// Extracts the numeric model code from a TrainTrip (e.g. "701" from "SUBORNO EXPRESS (701)").
  static String extractTrainModel(TrainTrip train) {
    if (train.trainModel.trim().isNotEmpty &&
        train.trainModel.trim() != 'null') {
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
        final time = DateFormat(
          pattern,
          'en_US',
        ).parseStrict(cleaned.toUpperCase());
        return time.hour * 60 + time.minute;
      } on FormatException {
        // try next
      }
    }
    return null;
  }

  static final _routeRequests = <String, Future<List<RouteStation>>>{};

  /// One bounded, paced route request is shared by both tabs and all callers.
  /// Failed/empty routes are never cached and never trigger an unpaced fallback.
  static Future<List<RouteStation>> fetchTrainRouteStations({
    required String trainModel,
    required String departureDate,
    AuthSession? auth,
  }) {
    final journeyDate = JourneySchedule.parseDate(departureDate);
    if (journeyDate == null || trainModel.trim().isEmpty) {
      return Future.error(
        StateError('Train route or journey date is unavailable.'),
      );
    }
    final dateParam = DateFormat('yyyy-MM-dd').format(journeyDate);
    final cached = TrainRouteCache.getRoute(trainModel, dateParam);
    if (cached != null) {
      return Future.value([
        for (var i = 0; i < cached.length; i++)
          RouteStation.fromJson(cached[i], i),
      ]);
    }
    final key = '${trainModel.trim().toLowerCase()}:$dateParam';
    return _routeRequests.putIfAbsent(key, () async {
      try {
        final session = auth ?? await AuthSession.load();
        if (session == null) {
          throw StateError('Please log in to load train stops.');
        }
        final response = await RailApiClient.request(
          operation: 'train_routes',
          method: 'POST',
          payload: {
            'model': trainModel.trim(),
            'departure_date_time': dateParam,
          },
          auth: session,
        );
        if (response.statusCode != 200) {
          throw StateError(
            'Unable to load train stops (${response.statusCode}). Try again.',
          );
        }
        final decoded = jsonDecode(response.body);
        final raw = decoded is Map && decoded['data'] is Map
            ? decoded['data']['routes']
            : null;
        if (raw is! List ||
            raw.length < 2 ||
            raw.any((r) => r is! Map || '${r['city'] ?? ''}'.trim().isEmpty)) {
          throw StateError('Train stops are unavailable. Please try again.');
        }
        final routes = raw
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        TrainRouteCache.setRoute(trainModel, dateParam, routes);
        return [
          for (var i = 0; i < routes.length; i++)
            RouteStation.fromJson(routes[i], i),
        ];
      } finally {
        _routeRequests.remove(key);
      }
    });
  }

  static String _stationKey(String value) =>
      value.trim().replaceAll(RegExp(r'[_\s]+'), ' ').toLowerCase();

  /// Exact normalized names avoid matching a short station to a different stop.
  static int findStationIndex(List<RouteStation> stations, String query) {
    final normalized = _stationKey(query);
    if (normalized.isEmpty) return -1;
    return stations.indexWhere(
      (s) =>
          _stationKey(s.city) == normalized ||
          _stationKey(s.name) == normalized,
    );
  }

  /// [date] is the original boarding date, not necessarily the route's first day.
  static String boardingDate({
    required List<RouteStation> stations,
    required RouteStation boarding,
    required String referenceStation,
    required String date,
  }) {
    final journeyDate = JourneySchedule.parseDate(date);
    final reference = findStationIndex(stations, referenceStation);
    final target = findStationIndex(stations, boarding.city);
    if (journeyDate == null || reference < 0 || target < 0) {
      throw StateError('Boarding station or journey date is unavailable.');
    }
    final offsets = <int>[];
    var day = 0;
    int? previous;
    for (final station in stations) {
      for (final raw in [station.arrivalTime, station.departureTime]) {
        final time = parseMinutes(raw);
        if (time == null) continue;
        if (previous != null && time < previous) day++;
        previous = time;
      }
      offsets.add(day);
    }
    return DateFormat('dd-MMM-yyyy', 'en_US').format(
      journeyDate.add(Duration(days: offsets[target] - offsets[reference])),
    );
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
    bool includeOverlapping = false,
    bool Function()? cancelled,
    void Function(int checked, int total, String station)? onProgress,
    void Function(List<IntermediateJourney> results)? onResults,
  }) async {
    final journeyDate = JourneySchedule.parseDate(date);
    final model = extractTrainModel(train);
    if (journeyDate == null || model.isEmpty) {
      throw StateError(
        'Train route information is unavailable. Try searching again.',
      );
    }

    if (cancelled?.call() == true) return [];
    final stations = await fetchTrainRouteStations(
      trainModel: model,
      departureDate: date,
      auth: auth,
    );
    final start = findStationIndex(stations, from);
    final end = findStationIndex(stations, to);
    if (start < 0 || end <= start) {
      throw StateError(
        'The selected stations were not found in this train route.',
      );
    }
    final routes = TrainRouteCache.getRoute(
      model,
      DateFormat('yyyy-MM-dd').format(journeyDate),
    )!;
    String city(int i) => stations[i].city;

    TrainRouteCache.setIntermediate(
      train.tripNumber,
      from,
      to,
      List.generate(end - start - 1, (idx) => city(start + 1 + idx)),
    );

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
    final totalCandidateStops = end - start - 1;
    if (totalCandidateStops <= 0) return results;

    final dayOffsets = <int, int>{};
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
      if (parseMinutes('${routes[i]['departure_time'] ?? ''}') == null ||
          previous == null) {
        throw StateError(
          'Departure time for ${city(i)} is unavailable. Cannot safely search this connection.',
        );
      }
      dayOffsets[i] = day;
    }

    final firstLegTrips = <int, TrainTrip?>{};
    final secondLegTrips = <int, TrainTrip?>{};

    Future<List<IntermediateJourney>> checkStation(int i) async {
      if (cancelled?.call() == true) return const [];
      final secondDate = DateFormat(
        'dd-MMM-yyyy',
        'en_US',
      ).format(journeyDate.add(Duration(days: dayOffsets[i] ?? 0)));
      final first = sameRun(
        await ApiService.searchTrips(
          fromCity: canonicalStation(from),
          toCity: city(i),
          dateOfJourney: date,
          seatClass: seatClass,
          authSession: auth,
          silent: true,
        ),
      );
      if (first != null) firstLegTrips[i] = first;
      if (cancelled?.call() == true) return const [];

      final firstHasSeats = first != null &&
          first.seatTypes.any(
            (s) =>
                s.isAvailable &&
                (anyClass || s.type.toUpperCase() == requested),
          );
      if (!includeOverlapping && !firstHasSeats) {
        return const [];
      }

      final second = sameRun(
        await ApiService.searchTrips(
          fromCity: city(i),
          toCity: canonicalStation(to),
          dateOfJourney: secondDate,
          seatClass: seatClass,
          authSession: auth,
          silent: true,
        ),
      );
      if (second != null) secondLegTrips[i] = second;
      if (cancelled?.call() == true) return const [];
      if (second == null || first == null || !firstHasSeats) return const [];
      final stationJourneys = <IntermediateJourney>[];
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
          stationJourneys.add(
            IntermediateJourney(
              via: displayStation(city(i)),
              viaCity: city(i),
              leg1ToStation: city(i),
              leg2FromStation: city(i),
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
      return stationJourneys;
    }

    final stationResults = List<List<IntermediateJourney>>.filled(
      totalCandidateStops,
      const [],
    );
    var completedCount = 0;

    if (totalCandidateStops == 1) {
      if (cancelled?.call() == true) return [];
      onProgress?.call(0, 1, stations[start + 1].name);
      final list = await checkStation(start + 1);
      stationResults[0] = list;
      completedCount++;
      if (list.isNotEmpty && onResults != null) {
        onResults(List.unmodifiable(list));
      }
    } else {
      final queue = List.generate(totalCandidateStops, (idx) => idx);
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          if (cancelled?.call() == true) break;
          final idx = queue.removeAt(0);
          final stationIdx = start + 1 + idx;
          onProgress?.call(
            completedCount,
            totalCandidateStops,
            stations[stationIdx].name,
          );
          final list = await checkStation(stationIdx);
          stationResults[idx] = list;
          completedCount++;
          onProgress?.call(
            completedCount,
            totalCandidateStops,
            stations[stationIdx].name,
          );
          if (list.isNotEmpty && onResults != null) {
            final current = [for (final items in stationResults) ...items];
            onResults(List.unmodifiable(current));
          }
          // Pacing delay between candidate stations to prevent server overload/429
          if (queue.isNotEmpty && cancelled?.call() != true) {
            await Future.delayed(const Duration(milliseconds: 350));
          }
        }
      }

      // Strictly sequential station checks (concurrency=1) with pacing delay to protect server
      final concurrency = 1;
      await Future.wait(List.generate(concurrency, (_) => worker()));
    }

    final overlappingJourneys = <IntermediateJourney>[];
    if (includeOverlapping && cancelled?.call() != true) {
      // Find pairs (j, i) where station j comes before station i along the route.
      // Leg 1: from -> city(i)
      // Leg 2: city(j) -> to
      // Because j < i, the passenger holds overlapping tickets on the same train
      // between city(j) and city(i), covering the entire journey from 'from' to 'to'.
      for (var i = start + 1; i < end; i++) {
        final firstTrip = firstLegTrips[i];
        if (firstTrip == null) continue;

        for (var j = start + 1; j < i; j++) {
          final secondTrip = secondLegTrips[j];
          if (secondTrip == null) continue;

          final secondDate = DateFormat(
            'dd-MMM-yyyy',
            'en_US',
          ).format(journeyDate.add(Duration(days: dayOffsets[j] ?? 0)));

          for (final seat in firstTrip.seatTypes) {
            if (!seat.isAvailable ||
                (tripIds.isNotEmpty && !tripIds.contains(seat.tripId)) ||
                (!anyClass && seat.type.toUpperCase() != requested)) {
              continue;
            }
            final other = secondTrip.seatTypes
                .where(
                  (s) =>
                      s.isAvailable &&
                      s.type == seat.type &&
                      (tripIds.isEmpty || s.tripId == seat.tripId),
                )
                .firstOrNull;
            if (other != null) {
              overlappingJourneys.add(
                IntermediateJourney(
                  via: '${displayStation(city(j))} & ${displayStation(city(i))}',
                  viaCity: '${city(j)} - ${city(i)}',
                  leg1ToStation: city(i),
                  leg2FromStation: city(j),
                  firstDate: date,
                  secondDate: secondDate,
                  first: firstTrip,
                  second: secondTrip,
                  firstSeat: seat,
                  secondSeat: other,
                ),
              );
            }
          }
        }
      }
    }

    final combined = <IntermediateJourney>[
      for (final items in stationResults) ...items,
      ...overlappingJourneys,
    ];

    combined.sort((a, b) {
      if (a.isOverlapping != b.isOverlapping) {
        return a.isOverlapping ? 1 : -1;
      }
      return b.seats.compareTo(a.seats);
    });

    if (cancelled?.call() != true) {
      onProgress?.call(totalCandidateStops, totalCandidateStops, '');
      if (onResults != null && overlappingJourneys.isNotEmpty) {
        onResults(List.unmodifiable(combined));
      }
    }
    return combined;
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
    if (from.sequence >= to.sequence) {
      throw StateError('Choose a destination after your boarding station.');
    }
    final res = await ApiService.searchTrips(
      fromCity: from.city,
      toCity: to.city,
      dateOfJourney: date,
      seatClass: seatClass,
      authSession: auth,
      silent: true,
    );
    final targetClean = targetTrain.tripNumber
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
    final targetModel = extractTrainModel(targetTrain);
    final matched = res.trains
        .where(
          (c) =>
              c.tripNumber.replaceAll(RegExp(r'\s+'), '').toLowerCase() ==
                  targetClean ||
              (targetModel.isNotEmpty && extractTrainModel(c) == targetModel),
        )
        .firstOrNull;
    final requested = seatClass?.trim().toUpperCase();
    final anyClass =
        requested == null ||
        requested.isEmpty ||
        requested == 'ALL' ||
        requested == 'RANDOM';
    final available = (matched?.availableSeatTypes ?? <SeatType>[])
        .where((s) => anyClass || s.type.toUpperCase() == requested)
        .toList();
    final count = available.fold<int>(0, (sum, s) => sum + s.seatCounts.online);
    return StationPairAvailability(
      from: from,
      to: to,
      train: matched,
      hasSeats: count > 0,
      totalSeats: count,
      seatTypes: available,
      date: date,
    );
  }
}
