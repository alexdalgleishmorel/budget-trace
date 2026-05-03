import 'budget_category.dart';
import 'transaction.dart';

class BudgetCycle {
  const BudgetCycle({
    required this.label,
    required this.root,
    required this.transactions,
  });

  final String label;
  final BudgetCategory root;
  final List<Transaction> transactions;
}
