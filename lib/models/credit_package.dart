class CreditPackage {
  final String id;
  final double amount;
  final int credits;
  final String label;
  final bool popular;

  const CreditPackage({
    required this.id,
    required this.amount,
    required this.credits,
    required this.label,
    this.popular = false,
  });

  factory CreditPackage.fromJson(Map<String, dynamic> json) {
    final amount = (json['amount'] as num?)?.toDouble() ?? 50.0;
    final credits = (json['credits'] as num?)?.toInt() ?? 10;
    return CreditPackage(
      id: json['id'] as String? ?? 'pkg_${credits}_${amount.toInt()}',
      amount: amount,
      credits: credits,
      label: json['label'] as String? ?? '$credits ক্রেডিট (৳${amount.toInt()})',
      popular: json['popular'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'credits': credits,
    'label': label,
    'popular': popular,
  };
}
