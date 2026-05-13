import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Horizontal bar list. Cleaner than a vertical bar chart at small grid
/// sizes (labels stay readable) and works for both spend-by-category and
/// top-merchants metric payloads.
class BarWidgetBody extends StatelessWidget {
  const BarWidgetBody({super.key, required this.data});
  final WidgetData data;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final items = data.asCategoricalItems('categories');
    if (items.isEmpty) return _empty(bt);

    final maxVal =
        items.fold<double>(0, (m, it) => it.value > m ? it.value : m);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final it = items[i];
        final pct = maxVal == 0 ? 0.0 : (it.value / maxVal).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    it.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12, color: bt.ink2, fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '\$${fmtMoneyDecimal(it.value)}',
                  style: TextStyle(
                    fontSize: 12, color: bt.ink3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (_, c) => Stack(children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: bt.surface2,
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                  ),
                ),
                Container(
                  width: c.maxWidth * pct,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _palette(bt, i),
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    boxShadow: [
                      BoxShadow(
                        color: _palette(bt, i).withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  static Color _palette(BudgetTheme bt, int i) {
    return bt.categoryColors[i % bt.categoryColors.length];
  }

  Widget _empty(BudgetTheme bt) => Center(
        child: Text('No data',
            style: TextStyle(fontSize: 12, color: bt.ink4)),
      );
}
