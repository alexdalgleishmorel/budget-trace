import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

/// Default presentational card. After the Arctic rework this is a thin
/// wrapper around [GlassSurface] so every existing call-site inherits the
/// new frosted-glass look without per-site changes.
class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.child,
    this.padding,
    this.clipContent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  /// Retained for API compatibility — GlassSurface always clips its content
  /// with a ClipRRect, so this flag is effectively a no-op now.
  final bool clipContent;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      tier: GlassTier.t1,
      radius: 20,
      padding: padding,
      child: child,
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
        fontSize: 11,
        letterSpacing: 0.06 * 11,
        color: context.bt.ink3,
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
        color: context.bt.glassBorder,
      );
}
