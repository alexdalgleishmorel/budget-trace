import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'cat_icon.dart';

/// Top-left profile affordance shared by all three tab headers on mobile.
/// Replaces the per-screen page title (Categories / Expenses / Insights) —
/// the bottom tab bar already tells the user which tab they're on, so the
/// title was redundant. Tapping pushes the AccountScreen modal.
///
/// Desktop has its own Account button in the side nav and doesn't render
/// this widget.
class MobileSettingsIcon extends StatelessWidget {
  const MobileSettingsIcon({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: bt.surface,
          border: Border.all(color: bt.ruleStrong),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        alignment: Alignment.center,
        child: BudgetIcons.build(
          'profile',
          size: 16,
          strokeWidth: 1.8,
          color: bt.ink2,
        ),
      ),
    );
  }
}
