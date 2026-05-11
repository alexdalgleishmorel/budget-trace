import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Big-number widget. Shows the headline value vertically centred, with an
/// optional delta chip below versus a comparison period. No chart —
/// reach for a `timeseries` widget when you want a trend.
class QueryValueWidgetBody extends StatelessWidget {
  const QueryValueWidgetBody({super.key, required this.data});
  final WidgetData data;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final value = data.queryValue;
    if (value == null) {
      return Center(
        child: Text('—',
            style: TextStyle(fontSize: 20, color: bt.ink4)),
      );
    }

    final fmt = data.queryValueFormat;
    final comparison = data.queryComparison;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatValue(value, fmt),
              maxLines: 1,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: bt.ink,
              ),
            ),
          ),
          if (comparison != null) ...[
            const SizedBox(height: 6),
            _ComparisonChip(comparison: comparison),
          ],
        ],
      ),
    );
  }
}

String _formatValue(double v, String fmt) {
  switch (fmt) {
    case 'currency':
      return '\$${fmtMoneyDecimal(v)}';
    case 'percent':
      return '${v.toStringAsFixed(1)}%';
    case 'number':
      return fmtMoney(v);
  }
  return v.toStringAsFixed(2);
}

class _ComparisonChip extends StatelessWidget {
  const _ComparisonChip({required this.comparison});
  final Map<String, dynamic> comparison;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final pct = comparison['delta_pct'];
    final abs = (comparison['delta_abs'] as num?)?.toDouble() ?? 0.0;
    final label = comparison['label'] as String? ?? '';
    final up = abs >= 0;
    final color = up ? bt.neg : bt.pos; // more spend = worse
    final bg = up ? bt.negBg : bt.posBg;
    final sign = up ? '↑' : '↓';
    final pctText = pct is num ? '${pct.abs().toStringAsFixed(1)}%' : '—';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
          child: Text(
            '$sign $pctText',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (label.isNotEmpty)
          Text(label, style: TextStyle(fontSize: 11, color: bt.ink4)),
      ],
    );
  }
}

