class CreditTransaction {
  final String id;
  final String phone;
  final String bkashSender;
  final String trxId;
  final double amount;
  final int credits;
  final String status; // 'Approved', 'Pending', 'Rejected'
  final bool applied;
  final DateTime createdAt;

  CreditTransaction({
    required this.id,
    required this.phone,
    required this.bkashSender,
    required this.trxId,
    required this.amount,
    required this.credits,
    required this.status,
    this.applied = false,
    required this.createdAt,
  });

  static DateTime _parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    try {
      if (val is DateTime) return val;
      if (val.runtimeType.toString().contains('Timestamp')) {
        return (val as dynamic).toDate() as DateTime;
      }
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
    } catch (_) {}
    return DateTime.now();
  }

  factory CreditTransaction.fromJson(Map<String, dynamic> json) {
    return CreditTransaction(
      id: json['id']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      bkashSender: json['bkashSender']?.toString() ?? '',
      trxId: json['trxId']?.toString() ?? '',
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toDouble()
          : double.tryParse('${json['amount']}') ?? 0.0,
      credits: (json['credits'] is int)
          ? json['credits']
          : int.tryParse('${json['credits']}') ?? 0,
      status: json['status']?.toString() ?? 'Pending',
      applied: json['applied'] == true,
      createdAt: _parseDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'bkashSender': bkashSender,
        'trxId': trxId,
        'amount': amount,
        'credits': credits,
        'status': status,
        'applied': applied,
        'createdAt': createdAt.toIso8601String(),
      };
}
