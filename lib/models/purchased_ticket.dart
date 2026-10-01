class PurchasedTicket {
  final int orderId;
  final String journeyDate;
  final String bookingDate;
  final String tripNumber;
  final String pnr;
  final int orderStatus;
  final String? printDate;
  final int tripId;
  final int originCityId;
  final int userId;
  final bool isApplicableRefund;
  final bool isRefundInProgress;
  final bool isPrinted;
  final bool isRefunded;

  PurchasedTicket({
    required this.orderId,
    required this.journeyDate,
    required this.bookingDate,
    required this.tripNumber,
    required this.pnr,
    required this.orderStatus,
    this.printDate,
    required this.tripId,
    required this.originCityId,
    required this.userId,
    this.isApplicableRefund = false,
    this.isRefundInProgress = false,
    this.isPrinted = false,
    this.isRefunded = false,
  });

  /// Extracts the train name without class brackets, e.g. "MAHANAGAR GODHULI (703)"
  String get trainName {
    final idx = tripNumber.indexOf('[');
    if (idx > 0) return tripNumber.substring(0, idx).trim();
    return tripNumber;
  }

  /// Extracts the seat class tag if present, e.g. "F_SEAT"
  String get seatClass {
    final match = RegExp(r'\[(.*?)\]').firstMatch(tripNumber);
    return match?.group(1) ?? '';
  }

  bool get isConfirmed => orderStatus == 1;

  factory PurchasedTicket.fromJson(Map<String, dynamic> json) {
    final refund = json['refund_validity_info'] as Map<String, dynamic>? ?? {};
    return PurchasedTicket(
      orderId: json['order_id'] is int
          ? json['order_id'] as int
          : int.tryParse(json['order_id']?.toString() ?? '0') ?? 0,
      journeyDate: json['journey_date']?.toString() ?? '',
      bookingDate: json['booking_date']?.toString() ?? '',
      tripNumber: json['trip_number']?.toString() ?? '',
      pnr: json['pnr']?.toString() ?? '',
      orderStatus: json['order_status'] is int
          ? json['order_status'] as int
          : int.tryParse(json['order_status']?.toString() ?? '1') ?? 1,
      printDate: json['print_date']?.toString(),
      tripId: json['trip_id'] is int
          ? json['trip_id'] as int
          : int.tryParse(json['trip_id']?.toString() ?? '0') ?? 0,
      originCityId: json['origin_city_id'] is int
          ? json['origin_city_id'] as int
          : int.tryParse(json['origin_city_id']?.toString() ?? '0') ?? 0,
      userId: json['user_id'] is int
          ? json['user_id'] as int
          : int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
      isApplicableRefund: refund['is_applicable'] == true,
      isRefundInProgress: refund['is_in_progress'] == true,
      isPrinted: refund['is_printed'] == true,
      isRefunded: refund['is_refunded'] == true,
    );
  }
}
