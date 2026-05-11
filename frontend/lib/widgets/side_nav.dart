import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'cat_icon.dart';
import 'cycle_dropdown.dart';

class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.current,
    required this.onNav,
    required this.cycleLabel,
    required this.cycleLabels,
    required this.onCycleChange,
    required this.onOpenAccount,
    this.showWidgets = true,
  });

  final int current;
  final ValueChanged<int> onNav;
  final String cycleLabel;
  final List<String> cycleLabels;
  final ValueChanged<String> onCycleChange;
  final VoidCallback onOpenAccount;

  /// When false, hide the Widgets entry. Other tab indices keep their
  /// stable positions: 0=Categories, 1=Expenses, 3=Insights.
  final bool showWidgets;

  // Stable indices across the app:
  //   0=Categories, 1=Expenses, 2=Widgets, 3=Insights.
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
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: bt.bg,
        border: Border(right: BorderSide(color: bt.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand
          Padding(
            padding: const EdgeInsets.only(bottom: 36, left: 4),
            child: Text(
              'Expense Trace',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: bt.ink,
                letterSpacing: -0.22,
              ),
            ),
          ),
          ...List.generate(visibleItems.length, (i) {
            final item = visibleItems[i];
            final active = item.idx == current;
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: active ? bt.ink : Colors.transparent,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                child: InkWell(
                  onTap: () => onNav(item.idx),
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                  hoverColor: active ? null : bt.surface2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        item.icon == 'grid'
                            ? Icon(
                                Icons.grid_view_outlined,
                                size: 18,
                                color: active ? bt.bg : bt.ink2,
                              )
                            : BudgetIcons.build(
                                item.icon,
                                size: 18,
                                strokeWidth: 1.6,
                                color: active ? bt.bg : bt.ink2,
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: active ? bt.bg : bt.ink2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Cycle dropdown — only meaningful on Expenses tab
          if (current == 1) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 6),
                  child: BudgetLabel('Cycle'),
                ),
                CycleDropdown(
                  value: cycleLabel,
                  options: cycleLabels,
                  onChange: onCycleChange,
                  openAbove: true,
                  expand: true,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: bt.rule))),
            padding: const EdgeInsets.only(top: 12),
            child: InkWell(
              onTap: onOpenAccount,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    BudgetIcons.build('profile',
                        size: 18, strokeWidth: 1.8, color: bt.ink3),
                    const SizedBox(width: 10),
                    Text(
                      'Account',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: bt.ink2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Alias used inside SideNav — imported from budget_card.dart
class BudgetLabel extends StatelessWidget {
  const BudgetLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          letterSpacing: 0.12 * 10.5,
          color: context.bt.ink4,
          fontWeight: FontWeight.w500,
        ),
      );
}
