import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Animated track + thumb plus a `LIGHT`/`DARK` mono label.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key, required this.isDark, required this.onToggle});

  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return InkWell(
      onTap: onToggle,
      borderRadius: BudgetRadius.btnBR,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 18,
              decoration: BoxDecoration(
                color: isDark ? bt.ink2 : bt.surface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: bt.ruleStrong),
              ),
              child: Stack(children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  left: isDark ? 16 : 1,
                  top: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: bt.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: bt.ruleStrong),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Text(
              isDark ? 'DARK' : 'LIGHT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: bt.ink3,
                letterSpacing: 0.66,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
