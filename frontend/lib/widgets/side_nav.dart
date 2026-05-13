import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'cat_icon.dart';
import 'cycle_dropdown.dart';
import 'glass.dart';

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
    (idx: 3, icon: 'sparkle', label: 'Insights'),
  ];

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final visibleItems =
        _items.where((it) => showWidgets || it.idx != 2).toList();
    return Container(
      width: 220,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: bt.glassBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(),
          const SizedBox(height: 28),
          ...List.generate(visibleItems.length, (i) {
            final item = visibleItems[i];
            final active = item.idx == current;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _NavItem(
                icon: item.icon,
                label: item.label,
                active: active,
                onTap: () => onNav(item.idx),
              ),
            );
          }),
          const Spacer(),
          // Cycle dropdown — only meaningful on Expenses tab
          if (current == 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 6),
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
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: bt.glassBorder))),
            padding: const EdgeInsets.only(top: 12),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onOpenAccount,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  child: Row(
                    children: [
                      BudgetIcons.build('profile',
                          size: 18, strokeWidth: 1.6, color: bt.ink3),
                      const SizedBox(width: 10),
                      Text(
                        'Account',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: bt.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GradientIconTile(
            size: 26,
            radius: 8,
            child: BudgetIcons.build(
              'results',
              size: 14,
              strokeWidth: 1.8,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Expense',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: bt.ink,
                    letterSpacing: -0.015 * 14,
                    height: 1.1,
                  ),
                ),
                Text(
                  'Visualizer',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: bt.ink.withValues(alpha: 0.65),
                    letterSpacing: -0.015 * 14,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
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
    final iconColor = active ? bt.ink : bt.ink3;
    final labelColor = active ? bt.ink : bt.ink3;
    final fontWeight = active ? FontWeight.w600 : FontWeight.w500;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          BudgetIcons.build(
            icon,
            size: 18,
            strokeWidth: 1.6,
            color: iconColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: fontWeight,
                color: labelColor,
                letterSpacing: -0.005 * 14,
              ),
            ),
          ),
        ],
      ),
    );

    final body = SizedBox(height: 42, child: Center(child: row));

    if (active) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: GlassSurface(
            tier: GlassTier.t2,
            radius: 12,
            elevated: false,
            sheen: false,
            child: body,
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: bt.glass1,
        child: body,
      ),
    );
  }
}

// Alias used inside SideNav — re-exported for callers via this file.
class BudgetLabel extends StatelessWidget {
  const BudgetLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.06 * 11,
          color: context.bt.ink3,
          fontWeight: FontWeight.w500,
        ),
      );
}
