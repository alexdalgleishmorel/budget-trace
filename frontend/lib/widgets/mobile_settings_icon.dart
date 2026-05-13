import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'cat_icon.dart';
import 'glass.dart';

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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: GlassSurface(
          tier: GlassTier.t2,
          radius: 10,
          elevated: false,
          sheen: false,
          padding: const EdgeInsets.all(9),
          child: BudgetIcons.build(
            'profile',
            size: 16,
            strokeWidth: 1.6,
            color: bt.ink2,
          ),
        ),
      ),
    );
  }
}
