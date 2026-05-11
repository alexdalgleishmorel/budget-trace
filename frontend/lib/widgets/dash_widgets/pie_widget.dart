import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Donut chart with a legend. Donut over full pie because the center
/// surfaces the total prominently — useful at a glance on a small tile.
class PieWidgetBody extends StatelessWidget {
  const PieWidgetBody({super.key, required this.data});
  final WidgetData data;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final items = data.asCategoricalItems('slices');
    if (items.isEmpty) {
      return Center(
        child: Text('No data',
            style: TextStyle(fontSize: 12, color: bt.ink4)),
      );
    }
    final total =
        (data.data['total'] as num?)?.toDouble() ??
            items.fold<double>(0, (m, it) => m + it.value);
    final palette = _palette(bt, items.length);
    return LayoutBuilder(
      builder: (_, c) {
        final compact = c.maxWidth < 240;
        final chartSize = compact
            ? c.maxHeight.clamp(80.0, 160.0)
            : math.min(c.maxWidth * 0.45, c.maxHeight);
        return Flex(
          direction: compact ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: chartSize.toDouble(),
              height: chartSize.toDouble(),
              child: CustomPaint(
                painter: _DonutPainter(
                  values: items.map((it) => it.value).toList(),
                  colors: palette,
                  holeColor: bt.surface,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '\$${fmtMoney(total)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: bt.ink,
                        ),
                      ),
                      Text(
                        'Total',
                        style: TextStyle(fontSize: 10, color: bt.ink4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: compact ? 0 : 12, height: compact ? 8 : 0),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final it = items[i];
                  final pct = total == 0 ? 0 : (it.value / total * 100);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: palette[i % palette.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            it.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: bt.ink2),
                          ),
                        ),
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 11, color: bt.ink4,
                              fontFeatures:
                                  const [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static List<Color> _palette(BudgetTheme bt, int n) {
    final base = [
      bt.ink, bt.pos, bt.warn, bt.neg, bt.ink3,
      bt.tile3, bt.tile4, bt.tile5,
    ];
    return List<Color>.generate(n, (i) => base[i % base.length]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.holeColor,
  });

  final List<double> values;
  final List<Color> colors;
  final Color holeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 2;
    final innerR = radius * 0.62;
    final rect = Rect.fromCircle(center: center, radius: radius);

    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();
      canvas.drawPath(path, paint);
      start += sweep;
    }

    // Punch the center hole by overdrawing in the card's surface colour.
    canvas.drawCircle(center, innerR, Paint()..color = holeColor);
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values || old.colors != colors || old.holeColor != holeColor;
}
