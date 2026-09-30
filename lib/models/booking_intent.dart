import 'dart:math';
import 'train_trip.dart';
import 'seat_type.dart';

class BookingIntent {
  final bool autoReserve;
  final int quantity;
  final double? maxFare;
  final bool autoVerify;
  final List<String> targetTrains;

  const BookingIntent({
    this.autoReserve = false,
    this.quantity = 1,
    this.maxFare,
    this.autoVerify = false,
    this.targetTrains = const [],
  });

  Map<String, dynamic> toJson() => {
    'autoReserve': autoReserve,
    'quantity': quantity,
    'maxFare': maxFare,
    'autoVerify': autoVerify,
    'targetTrains': targetTrains,
  };

  factory BookingIntent.fromJson(Map<String, dynamic> json) => BookingIntent(
    autoReserve: json['autoReserve'] == true,
    quantity: (json['quantity'] is int ? json['quantity'] as int : 1).clamp(1, 4),
    maxFare: json['maxFare'] is num ? (json['maxFare'] as num).toDouble() : null,
    autoVerify: json['autoVerify'] == true,
    targetTrains: (json['targetTrains'] is List)
        ? (json['targetTrains'] as List).map((e) => e.toString()).toList()
        : (json['targetTrain'] != null && json['targetTrain'].toString().isNotEmpty
            ? [json['targetTrain'].toString()]
            : const []),
  );

  BookingIntent copyWith({
    bool? autoReserve,
    int? quantity,
    double? maxFare,
    bool? autoVerify,
    List<String>? targetTrains,
  }) {
    return BookingIntent(
      autoReserve: autoReserve ?? this.autoReserve,
      quantity: quantity ?? this.quantity,
      maxFare: maxFare ?? this.maxFare,
      autoVerify: autoVerify ?? this.autoVerify,
      targetTrains: targetTrains ?? this.targetTrains,
    );
  }

  (TrainTrip, SeatType)? choose(
    List<TrainTrip> trains, {
    String? train,
    List<String>? targetTrains,
    String? seatClass,
    Random? random,
  }) {
    final matches = <(TrainTrip, SeatType)>[];
    final effectiveTrains = (targetTrains != null && targetTrains.isNotEmpty)
        ? targetTrains
        : (this.targetTrains.isNotEmpty
            ? this.targetTrains
            : (train != null && train.isNotEmpty && train.toUpperCase() != 'ALL'
                ? [train]
                : const <String>[]));

    for (final item in trains) {
      if (effectiveTrains.isNotEmpty &&
          !effectiveTrains.any((t) => t.trim().toLowerCase() == item.tripNumber.trim().toLowerCase())) {
        continue;
      }
      for (final seat in item.seatTypes) {
        if (seatClass != null &&
            seatClass.toUpperCase() != 'ALL' &&
            seatClass.toUpperCase() != 'RANDOM' &&
            seat.type.toUpperCase() != seatClass.toUpperCase()) continue;
        final fare = double.tryParse(seat.fare);
        if (seat.seatCounts.online < quantity || fare == null || !fare.isFinite || fare < 0) continue;
        if (maxFare != null && fare + seat.vatAmount > maxFare!) continue;
        if (seat.tripId == null || seat.tripRouteId == null) continue;
        matches.add((item, seat));
      }
    }
    if (matches.isEmpty) return null;
    return matches[(random ?? Random.secure()).nextInt(matches.length)];
  }
}
