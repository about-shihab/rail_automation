class SeatItem {
  final bool isHidden;
  final int seatAvailability; // 1 = available, 0 = booked
  final String seatNumber;
  final int ticketId;
  final int ticketType;

  SeatItem({
    required this.isHidden,
    required this.seatAvailability,
    required this.seatNumber,
    required this.ticketId,
    required this.ticketType,
  });

  bool get isAvailable => seatAvailability == 1 && seatNumber.isNotEmpty && !isHidden;
  bool get isEmptySpace => seatNumber.trim().isEmpty || isHidden;

  factory SeatItem.fromJson(Map<String, dynamic> json) {
    return SeatItem(
      isHidden: json['isHidden'] == true,
      seatAvailability: json['seat_availability'] is int
          ? json['seat_availability']
          : int.tryParse('${json['seat_availability']}') ?? 0,
      seatNumber: json['seat_number']?.toString() ?? '',
      ticketId: json['ticket_id'] is int
          ? json['ticket_id']
          : int.tryParse('${json['ticket_id']}') ?? 0,
      ticketType: json['ticket_type'] is int
          ? json['ticket_type']
          : int.tryParse('${json['ticket_type']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'isHidden': isHidden,
        'seat_availability': seatAvailability,
        'seat_number': seatNumber,
        'ticket_id': ticketId,
        'ticket_type': ticketType,
      };
}

class CoachLayout {
  final String floorName;
  final int seatFloor;
  final int seatType;
  final int fareTypeId;
  final String seatFareType;
  final bool seatAvailability;
  final String seatFare;
  final List<List<SeatItem>> layout;

  CoachLayout({
    required this.floorName,
    required this.seatFloor,
    required this.seatType,
    required this.fareTypeId,
    required this.seatFareType,
    required this.seatAvailability,
    required this.seatFare,
    required this.layout,
  });

  /// Count of online seats available in this coach
  int get availableSeatsCount {
    int count = 0;
    for (final row in layout) {
      for (final seat in row) {
        if (seat.isAvailable) count++;
      }
    }
    return count;
  }

  factory CoachLayout.fromJson(Map<String, dynamic> json) {
    final rawLayout = json['layout'] as List? ?? [];
    final List<List<SeatItem>> parsedLayout = [];

    for (final row in rawLayout) {
      if (row is List) {
        final List<SeatItem> parsedRow = [];
        for (final seat in row) {
          if (seat is Map<String, dynamic>) {
            parsedRow.add(SeatItem.fromJson(seat));
          }
        }
        parsedLayout.add(parsedRow);
      }
    }

    return CoachLayout(
      floorName: json['floor_name']?.toString() ?? '',
      seatFloor: json['seat_floor'] is int
          ? json['seat_floor']
          : int.tryParse('${json['seat_floor']}') ?? 1,
      seatType: json['seat_type'] is int
          ? json['seat_type']
          : int.tryParse('${json['seat_type']}') ?? 1,
      fareTypeId: json['fare_type_id'] is int
          ? json['fare_type_id']
          : int.tryParse('${json['fare_type_id']}') ?? 1,
      seatFareType: json['seat_fare_type']?.toString() ?? 'Economy',
      seatAvailability: json['seat_availability'] == true,
      seatFare: json['seat_fare']?.toString() ?? '450.00',
      layout: parsedLayout,
    );
  }

  Map<String, dynamic> toJson() => {
        'floor_name': floorName,
        'seat_floor': seatFloor,
        'seat_type': seatType,
        'fare_type_id': fareTypeId,
        'seat_fare_type': seatFareType,
        'seat_availability': seatAvailability,
        'seat_fare': seatFare,
        'layout': layout.map((row) => row.map((seat) => seat.toJson()).toList()).toList(),
      };
}

class SeatLayoutResponse {
  final List<CoachLayout> coaches;

  SeatLayoutResponse({required this.coaches});

  int get totalAvailableSeats =>
      coaches.fold(0, (sum, coach) => sum + coach.availableSeatsCount);

  factory SeatLayoutResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final rawLayouts = data['seatLayout'] as List? ?? [];

    final coaches = rawLayouts
        .whereType<Map<String, dynamic>>()
        .map((c) => CoachLayout.fromJson(c))
        .toList();

    return SeatLayoutResponse(coaches: coaches);
  }
}
