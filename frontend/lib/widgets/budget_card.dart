import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.child,
    this.padding,
    this.clipContent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool clipContent;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    Widget content = padding != null ? Padding(padding: padding!, child: child) : child;
    return Container(
      decoration: BoxDecoration(
        color: bt.surface,
        borderRadius: BudgetRadius.cardBR,
        border: Border.all(color: bt.rule),
      ),
      clipBehavior: clipContent ? Clip.antiAlias : Clip.none,
      child: content,
    );
  }
}

class BudgetLabel extends StatelessWidget {
  const BudgetLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.12 * 10.5,
        color: context.bt.ink4,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class BudgetDivider extends StatelessWidget {
  const BudgetDivider({super.key});
  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        color: context.bt.rule,
      );
}
