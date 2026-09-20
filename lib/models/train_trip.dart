import 'seat_type.dart';

class BoardingPoint {
  final int? tripPointId;
  final int? locationId;
  final String locationName;
  final String locationTime;
  final String locationDate;

  BoardingPoint({
    this.tripPointId,
    this.locationId,
    required this.locationName,
    required this.locationTime,
    required this.locationDate,
  });

  factory BoardingPoint.fromJson(Map<String, dynamic> json) => BoardingPoint(
        tripPointId: json['trip_point_id'] is int
            ? json['trip_point_id']
            : int.tryParse('${json['trip_point_id']}'),
        locationId: json['location_id'] is int
            ? json['location_id']
            : int.tryParse('${json['location_id']}'),
        locationName: json['location_name'] ?? '',
        locationTime: json['location_time'] ?? '',
        locationDate: json['location_date'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'trip_point_id': tripPointId,
        'location_id': locationId,
        'location_name': locationName,
        'location_time': locationTime,
        'location_date': locationDate,
      };
}

class TrainTrip {
  final String tripNumber;
  final String departureDateTime;
  final String departureFullDate;
  final String departureDateTimeJd;
  final String arrivalDateTime;
  final String travelTime;
  final String originCityName;
  final String destinationCityName;
  final String trainModel;
  final bool isOpenForAll;
  final List<SeatType> seatTypes;
  final List<BoardingPoint> boardingPoints;

  TrainTrip({
    required this.tripNumber,
    required this.departureDateTime,
    required this.departureFullDate,
    required this.departureDateTimeJd,
    required this.arrivalDateTime,
    required this.travelTime,
    required this.originCityName,
    required this.destinationCityName,
    required this.trainModel,
    required this.isOpenForAll,
    required this.seatTypes,
    required this.boardingPoints,
  });

  int get totalOnlineSeats =>
      seatTypes.fold<int>(0, (sum, seat) => sum + seat.seatCounts.online);

  bool get hasAnyOnlineSeats => totalOnlineSeats > 0;

  List<SeatType> get availableSeatTypes =>
      seatTypes.where((seat) => seat.isAvailable).toList();

  SeatType? seatTypeByName(String typeName) {
    try {
      return seatTypes.firstWhere(
        (seat) => seat.type.toUpperCase() == typeName.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }

  factory TrainTrip.fromJson(Map<String, dynamic> json) {
    final rawSeats = json['seat_types'] as List<dynamic>? ?? [];
    final rawBoarding = json['boarding_points'] as List<dynamic>? ?? [];

    return TrainTrip(
      tripNumber: json['trip_number'] ?? '',
      departureDateTime: json['departure_date_time'] ?? '',
      departureFullDate: json['departure_full_date'] ?? '',
      departureDateTimeJd: json['departure_date_time_jd'] ?? '',
      arrivalDateTime: json['arrival_date_time'] ?? '',
      travelTime: json['travel_time'] ?? '',
      originCityName: json['origin_city_name'] ?? '',
      destinationCityName: json['destination_city_name'] ?? '',
      trainModel: '${json['train_model'] ?? ''}',
      isOpenForAll: json['is_open_for_all'] == true,
      seatTypes: rawSeats
          .map((item) => SeatType.fromJson(item as Map<String, dynamic>))
          .toList(),
      boardingPoints: rawBoarding
          .map((item) => BoardingPoint.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'trip_number': tripNumber,
        'departure_date_time': departureDateTime,
        'departure_full_date': departureFullDate,
        'departure_date_time_jd': departureDateTimeJd,
        'arrival_date_time': arrivalDateTime,
        'travel_time': travelTime,
        'origin_city_name': originCityName,
        'destination_city_name': destinationCityName,
        'train_model': trainModel,
        'is_open_for_all': isOpenForAll,
        'seat_types': seatTypes.map((e) => e.toJson()).toList(),
        'boarding_points': boardingPoints.map((e) => e.toJson()).toList(),
      };
}

class TripSearchResponse {
  final List<TrainTrip> trains;
  final String? selectedSeatClass;
  final String? hash;

  TripSearchResponse({
    required this.trains,
    this.selectedSeatClass,
    this.hash,
  });

  factory TripSearchResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final rawTrains = data['trains'] as List<dynamic>? ?? [];
    final extra = json['extra'] as Map<String, dynamic>? ?? {};

    return TripSearchResponse(
      trains: rawTrains
          .map((t) => TrainTrip.fromJson(t as Map<String, dynamic>))
          .toList(),
      selectedSeatClass: data['selected_seat_class'],
      hash: extra['hash'],
    );
  }
}
