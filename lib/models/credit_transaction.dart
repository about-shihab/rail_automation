class CreditTransaction {
  final String id;
  final String phone;
  final String bkashSender;
  final String trxId;
  final double amount;
  final int credits;
  final String status; // 'Approved', 'Pending', 'Rejected'
  final DateTime createdAt;

  CreditTransaction({
    required this.id,
    required this.phone,
    required this.bkashSender,
    required this.trxId,
    required this.amount,
    required this.credits,
    required this.status,
    required this.createdAt,
  });

  factory CreditTransaction.fromJson(Map<String, dynamic> json) {
    return CreditTransaction(
      id: json['id']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      bkashSender: json['bkashSender']?.toString() ?? '',
      trxId: json['trxId']?.toString() ?? '',
      amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : double.tryParse('${json['amount']}') ?? 0.0,
      credits: (json['credits'] is int) ? json['credits'] : int.tryParse('${json['credits']}') ?? 0,
      status: json['status']?.toString() ?? 'Approved',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
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
        'createdAt': createdAt.toIso8601String(),
      };
}
