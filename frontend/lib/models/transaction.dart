class Transaction {
  Transaction({
    required this.id,
    required this.date,
    required this.merchant,
    required this.amount,
    this.category,
  });

  final String id;
  final String date;
  String merchant;
  final double amount;
  String? category;

  Transaction copyWith({String? category}) => Transaction(
        id: id,
        date: date,
        merchant: merchant,
        amount: amount,
        category: category ?? this.category,
      );
}
