import 'dart:convert';

enum TripBookingStatus {
  successful,
  awaitingOtp,
  failed,
  expired,
}

class TripRecord {
  final String id;
  final String trainName;
  final String fromCity;
  final String toCity;
  final String dateOfJourney;
  final String seatClass;
  final List<String> seatNumbers;
  final String coachName;
  final double totalFare;
  final TripBookingStatus status;
  final String? failureReason;
  final DateTime createdAt;
  final bool isAutoBook;

  const TripRecord({
    required this.id,
    required this.trainName,
    required this.fromCity,
    required this.toCity,
    required this.dateOfJourney,
    required this.seatClass,
    this.seatNumbers = const [],
    this.coachName = '',
    this.totalFare = 0.0,
    required this.status,
    this.failureReason,
    required this.createdAt,
    this.isAutoBook = false,
  });

  String get statusDisplayName {
    switch (status) {
      case TripBookingStatus.successful:
        return 'SUCCESSFUL';
      case TripBookingStatus.awaitingOtp:
        return 'RESERVED';
      case TripBookingStatus.expired:
        return 'EXPIRED';
      case TripBookingStatus.failed:
        return 'FAILED';
    }
  }

  TripRecord copyWith({
    String? id,
    String? trainName,
    String? fromCity,
    String? toCity,
    String? dateOfJourney,
    String? seatClass,
    List<String>? seatNumbers,
    String? coachName,
    double? totalFare,
    TripBookingStatus? status,
    String? failureReason,
    DateTime? createdAt,
    bool? isAutoBook,
  }) {
    return TripRecord(
      id: id ?? this.id,
      trainName: trainName ?? this.trainName,
      fromCity: fromCity ?? this.fromCity,
      toCity: toCity ?? this.toCity,
      dateOfJourney: dateOfJourney ?? this.dateOfJourney,
      seatClass: seatClass ?? this.seatClass,
      seatNumbers: seatNumbers ?? this.seatNumbers,
      coachName: coachName ?? this.coachName,
      totalFare: totalFare ?? this.totalFare,
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
      createdAt: createdAt ?? this.createdAt,
      isAutoBook: isAutoBook ?? this.isAutoBook,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trainName': trainName,
        'fromCity': fromCity,
        'toCity': toCity,
        'dateOfJourney': dateOfJourney,
        'seatClass': seatClass,
        'seatNumbers': seatNumbers,
        'coachName': coachName,
        'totalFare': totalFare,
        'status': status.name,
        'failureReason': failureReason,
        'createdAt': createdAt.toIso8601String(),
        'isAutoBook': isAutoBook,
      };

  factory TripRecord.fromJson(Map<String, dynamic> json) {
    TripBookingStatus parseStatus(String? raw) {
      switch (raw?.toLowerCase()) {
        case 'successful':
        case 'confirmed':
        case 'readyforpayment':
          return TripBookingStatus.successful;
        case 'awaitingotp':
        case 'reserved':
        case 'reserving':
          return TripBookingStatus.awaitingOtp;
        case 'expired':
        case 'timedout':
          return TripBookingStatus.expired;
        default:
          return TripBookingStatus.failed;
      }
    }

    return TripRecord(
      id: json['id']?.toString() ?? '',
      trainName: json['trainName']?.toString() ?? 'Train',
      fromCity: json['fromCity']?.toString() ?? '',
      toCity: json['toCity']?.toString() ?? '',
      dateOfJourney: json['dateOfJourney']?.toString() ?? '',
      seatClass: json['seatClass']?.toString() ?? '',
      seatNumbers: json['seatNumbers'] is List
          ? (json['seatNumbers'] as List).map((e) => '$e').toList()
          : [],
      coachName: json['coachName']?.toString() ?? '',
      totalFare: json['totalFare'] is num
          ? (json['totalFare'] as num).toDouble()
          : double.tryParse('${json['totalFare'] ?? 0}') ?? 0.0,
      status: parseStatus(json['status']?.toString()),
      failureReason: json['failureReason']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isAutoBook: json['isAutoBook'] == true,
    );
  }
}
