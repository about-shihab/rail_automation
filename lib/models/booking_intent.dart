import 'dart:math';
import 'train_trip.dart';
import 'seat_type.dart';

class BookingIntent {
  final bool autoReserve;
  final int quantity;
  final double? maxFare;
  final bool autoVerify;
  const BookingIntent({this.autoReserve = false, this.quantity = 1, this.maxFare, this.autoVerify = false});
  Map<String, dynamic> toJson() => {'autoReserve': autoReserve, 'quantity': quantity, 'maxFare': maxFare, 'autoVerify': autoVerify};
  factory BookingIntent.fromJson(Map<String, dynamic> json) => BookingIntent(
    autoReserve: json['autoReserve'] == true,
    quantity: (json['quantity'] is int ? json['quantity'] as int : 1).clamp(1, 4),
    maxFare: json['maxFare'] is num ? (json['maxFare'] as num).toDouble() : null,
    autoVerify: json['autoVerify'] == true,
  );
  (TrainTrip, SeatType)? choose(List<TrainTrip> trains, {String? train, String? seatClass, Random? random}) {
    final matches = <(TrainTrip, SeatType)>[];
    for (final item in trains) {
      if (train != null && item.tripNumber.toLowerCase() != train.toLowerCase()) continue;
      for (final seat in item.seatTypes) {
        if (seatClass != null && seatClass != 'ALL' && seat.type.toUpperCase() != seatClass.toUpperCase()) continue;
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
