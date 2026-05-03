import 'package:flutter_test/flutter_test.dart';
import 'package:budget_trace/main.dart';

void main() {
  testWidgets('BudgetTrace app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BudgetTraceApp());
    expect(find.byType(BudgetTraceApp), findsOneWidget);
  });
}
