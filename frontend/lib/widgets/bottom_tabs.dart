import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'cat_icon.dart';
import 'glass.dart';

class BottomTabsBar extends StatelessWidget {
  const BottomTabsBar({
    super.key,
    required this.current,
    required this.onNav,
    this.showWidgets = true,
  });

  final int current;
  final ValueChanged<int> onNav;

  /// When false (widgets feature disabled), the Widgets tab is hidden but
  /// the remaining tab indices keep their stable positions: 0=Categories,
  /// 1=Expenses, 3=Insights.
  final bool showWidgets;

  // Stable indices across the app:
  //   0=Categories, 1=Expenses, 2=Widgets, 3=Insights.
  static const _items = [
    (idx: 0, icon: 'grid', label: 'Categories'),
    (idx: 1, icon: 'expenses', label: 'Expenses'),
    (idx: 2, icon: 'results', label: 'Widgets'),
    (idx: 3, icon: 'sparkle', label: 'Insights'),
  ];

  @override
  Widget build(BuildContext context) {
    final visibleItems =
        _items.where((it) => showWidgets || it.idx != 2).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: GlassSurface(
        tier: GlassTier.strong,
        radius: 24,
        padding: const EdgeInsets.all(6),
        child: Row(
          children: List.generate(visibleItems.length, (i) {
            final item = visibleItems[i];
            final active = item.idx == current;
            return Expanded(
              child: _BottomTab(
                icon: item.icon,
                label: item.label,
                active: active,
                onTap: () => onNav(item.idx),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final color = active ? bt.accent : bt.ink4;
    // SizedBox(width: infinity) forces the InkWell to claim the full width
    // of its tab slot. Without it, under loose constraints inside the
    // active GlassSurface's Stack, the Material+Column shrinks to the
    // narrowest content width and the Stack pins it to its default
    // top-start anchor — visibly shifting the icon left when the tab
    // becomes active.
    final content = SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BudgetIcons.build(
              icon,
              size: 22,
              strokeWidth: active ? 2.0 : 1.6,
              color: color,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );

    final inkwell = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: content,
      ),
    );

    if (!active) return inkwell;
    return GlassSurface(
      tier: GlassTier.t2,
      radius: 18,
      elevated: false,
      sheen: false,
      child: inkwell,
    );
  }
}
