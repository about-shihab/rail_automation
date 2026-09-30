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

  factory CreditPackage.fromJson(Map<String, dynamic> json, {String? docId}) {
    final rawAmount = json['amount'] ?? json['price'] ?? json['taka'] ?? json['tk'] ?? 50;
    final amount = (rawAmount is num)
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount.toString().replaceAll(RegExp(r'[^0-9.]'), '')) ?? 50.0;

    final rawCredits = json['credits'] ?? json['credit'] ?? json['tokens'] ?? json['token'] ?? json['count'] ?? 10;
    final credits = (rawCredits is num)
        ? rawCredits.toInt()
        : int.tryParse(rawCredits.toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 10;

    final id = json['id']?.toString().isNotEmpty == true
        ? json['id'].toString()
        : (docId?.isNotEmpty == true ? docId! : 'pkg_${credits}_${amount.toInt()}');

    final popular = json['popular'] == true ||
        json['popular']?.toString().toLowerCase() == 'true' ||
        json['is_popular'] == true ||
        json['badge']?.toString().toLowerCase() == 'popular';

    final label = json['label']?.toString().trim().isNotEmpty == true
        ? json['label'].toString().trim()
        : '$credits ক্রেডিট (৳${amount.toInt()})';

    return CreditPackage(
      id: id,
      amount: amount,
      credits: credits,
      label: label,
      popular: popular,
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
