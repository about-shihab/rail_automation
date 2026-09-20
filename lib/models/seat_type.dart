class SeatCounts {
  final int online;
  final int offline;
  final bool isDivided;

  SeatCounts({
    required this.online,
    required this.offline,
    required this.isDivided,
  });

  factory SeatCounts.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return SeatCounts(online: 0, offline: 0, isDivided: false);
    }
    return SeatCounts(
      online: json['online'] is int
          ? json['online']
          : int.tryParse('${json['online']}') ?? 0,
      offline: json['offline'] is int
          ? json['offline']
          : int.tryParse('${json['offline']}') ?? 0,
      isDivided: json['is_divided'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'online': online,
        'offline': offline,
        'is_divided': isDivided,
      };
}

class SeatType {
  final int key;
  final String type;
  final int? tripId;
  final int? tripRouteId;
  final int? routeId;
  final String fare;
  final num vatPercent;
  final num vatAmount;
  final SeatCounts seatCounts;

  SeatType({
    required this.key,
    required this.type,
    this.tripId,
    this.tripRouteId,
    this.routeId,
    required this.fare,
    required this.vatPercent,
    required this.vatAmount,
    required this.seatCounts,
  });

  bool get isAvailable => seatCounts.online > 0;

  String get displayName {
    switch (type.toUpperCase()) {
      case 'SNIGDHA':
        return 'Snigdha (AC Chair)';
      case 'S_CHAIR':
        return 'Shovon Chair';
      case 'AC_S':
        return 'AC Seat';
      case 'AC_B':
        return 'AC Berth';
      case 'F_SEAT':
        return 'First Class Seat';
      case 'F_BERTH':
        return 'First Class Berth';
      case 'SHOVON':
        return 'Shovon';
      default:
        return type;
    }
  }

  factory SeatType.fromJson(Map<String, dynamic> json) {
    return SeatType(
      key: json['key'] is int ? json['key'] : int.tryParse('${json['key']}') ?? 0,
      type: json['type'] ?? '',
      tripId: json['trip_id'] is int ? json['trip_id'] : int.tryParse('${json['trip_id']}'),
      tripRouteId: json['trip_route_id'] is int
          ? json['trip_route_id']
          : int.tryParse('${json['trip_route_id']}'),
      routeId: json['route_id'] is int
          ? json['route_id']
          : int.tryParse('${json['route_id']}'),
      fare: '${json['fare'] ?? '0.00'}',
      vatPercent: json['vat_percent'] ?? 0,
      vatAmount: json['vat_amount'] ?? 0,
      seatCounts: SeatCounts.fromJson(json['seat_counts'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'type': type,
        'trip_id': tripId,
        'trip_route_id': tripRouteId,
        'route_id': routeId,
        'fare': fare,
        'vat_percent': vatPercent,
        'vat_amount': vatAmount,
        'seat_counts': seatCounts.toJson(),
      };
}
