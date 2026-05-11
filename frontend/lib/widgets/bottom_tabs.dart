import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'cat_icon.dart';

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
  // Insights handles its own AI-disabled empty state. When `showWidgets`
  // is false, the Widgets entry is filtered out below.
  static const _items = [
    (idx: 0, icon: 'grid', label: 'Categories'),
    (idx: 1, icon: 'expenses', label: 'Expenses'),
    (idx: 2, icon: 'results', label: 'Widgets'),
    (idx: 3, icon: 'search', label: 'Insights'),
  ];

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final visibleItems =
        _items.where((it) => showWidgets || it.idx != 2).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: bt.surface.withValues(alpha: 0.72),
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              border: Border.all(color: bt.ruleStrong),
            ),
            padding: const EdgeInsets.all(6),
            child: Row(
              children: List.generate(visibleItems.length, (i) {
                final item = visibleItems[i];
                final active = item.idx == current;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onNav(item.idx),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: active ? bt.surface : Colors.transparent,
                        borderRadius: const BorderRadius.all(Radius.circular(14)),
                        border: Border.all(
                          color: active ? bt.rule : Colors.transparent,
                        ),
                        boxShadow: active
                            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))]
                            : null,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          item.icon == 'grid'
                              ? Icon(
                                  Icons.grid_view_outlined,
                                  size: 18,
                                  color: active ? bt.ink : bt.ink4,
                                )
                              : BudgetIcons.build(
                                  item.icon,
                                  size: 18,
                                  strokeWidth: 1.6,
                                  color: active ? bt.ink : bt.ink4,
                                ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                              color: active ? bt.ink : bt.ink4,
                              letterSpacing: 0.01,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
