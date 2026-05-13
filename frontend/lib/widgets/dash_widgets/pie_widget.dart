import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'chart_hover_tooltip.dart';

/// Donut chart with a legend. Donut over full pie because the center
/// surfaces the total prominently — useful at a glance on a small tile.
class PieWidgetBody extends StatefulWidget {
  const PieWidgetBody({super.key, required this.data});
  final WidgetData data;

  @override
  State<PieWidgetBody> createState() => _PieWidgetBodyState();
}

class _PieWidgetBodyState extends State<PieWidgetBody> {
  int? _hoveredIndex;
  Offset? _cursor;

  /// Compute which slice (if any) the cursor at [localPos] is over.
  /// Returns null when the cursor isn't on the donut ring.
  int? _hitTest(Offset localPos, Size size, List<double> values, double total) {
    if (total <= 0) return null;
    final outerR = math.min(size.width, size.height) / 2 - 2;
    final thickness = outerR * 0.28;
    final innerR = outerR - thickness;
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    final r = math.sqrt(dx * dx + dy * dy);
    if (r < innerR || r > outerR) return null;

    // Angle relative to 12 o'clock, going clockwise. Slices start at -π/2.
    var delta = math.atan2(dy, dx) - (-math.pi / 2);
    if (delta < 0) delta += 2 * math.pi;

    double cum = 0;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi;
      if (delta >= cum && delta < cum + sweep) return i;
      cum += sweep;
    }
    return null;
  }

  void _updateHover(Offset localPos, Size size, List<double> values, double total) {
    final idx = _hitTest(localPos, size, values, total);
    if (idx != _hoveredIndex || _cursor != localPos) {
      setState(() {
        _hoveredIndex = idx;
        _cursor = localPos;
      });
    }
  }

  void _clearHover() {
    if (_hoveredIndex != null || _cursor != null) {
      setState(() {
        _hoveredIndex = null;
        _cursor = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final items = widget.data.asCategoricalItems('slices');
    if (items.isEmpty) {
      return Center(
        child: Text('No data',
            style: TextStyle(fontSize: 12, color: bt.ink4)),
      );
    }
    final total =
        (widget.data.data['total'] as num?)?.toDouble() ??
            items.fold<double>(0, (m, it) => m + it.value);
    final values = items.map((it) => it.value).toList();
    final palette = _palette(bt, items.length);
    return LayoutBuilder(
      builder: (_, c) {
        final compact = c.maxWidth < 240;
        final chartSize = compact
            ? c.maxHeight.clamp(80.0, 160.0)
            : math.min(c.maxWidth * 0.45, c.maxHeight);
        final chartSide = chartSize.toDouble();
        return Flex(
          direction: compact ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: chartSide,
              height: chartSide,
              child: MouseRegion(
                onHover: (e) => _updateHover(
                    e.localPosition, Size(chartSide, chartSide), values, total),
                onExit: (_) => _clearHover(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _updateHover(
                      d.localPosition, Size(chartSide, chartSide), values, total),
                  onPanUpdate: (d) => _updateHover(
                      d.localPosition, Size(chartSide, chartSide), values, total),
                  onPanEnd: (_) => _clearHover(),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _DonutPainter(
                            values: values,
                            colors: palette,
                            trackColor: bt.glass2,
                            highlightedIndex: _hoveredIndex,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '\$${fmtMoney(total)}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: bt.ink,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: bt.ink3,
                                    letterSpacing: 0.06 * 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_hoveredIndex != null && _cursor != null)
                        PositionedChartTooltip(
                          cursor: _cursor!,
                          containerSize: Size(chartSide, chartSide),
                          estimatedWidth: 220,
                          estimatedHeight: 40,
                          child: ChartHoverTooltip(
                            lines: [
                              ChartTooltipLine(
                                swatchColor: palette[
                                    _hoveredIndex! % palette.length],
                                label: items[_hoveredIndex!].label,
                                value:
                                    '\$${fmtMoneyDecimal(items[_hoveredIndex!].value)}',
                                trailing: total == 0
                                    ? null
                                    : '${(items[_hoveredIndex!].value / total * 100).toStringAsFixed(1)}%',
                              ),
                            ],
                          ),
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
    return List<Color>.generate(
        n, (i) => bt.categoryColors[i % bt.categoryColors.length]);
  }
}

/// Stroked-arc donut. Drawing as a stroke (rather than filled wedges + a
/// hole-punch overdraw) avoids the faint inner-ring artifact you get when
/// the "hole" is a translucent surface over the wedge colors, and leaves
/// the donut's center genuinely transparent so the center label reads
/// against the underlying glass card.
class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
    this.highlightedIndex,
  });

  final List<double> values;
  final List<Color> colors;
  final Color trackColor;
  /// When non-null, that slice is drawn slightly thicker and other slices
  /// fade so the hovered slice pops.
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    final outerR = math.min(size.width, size.height) / 2 - 2;
    final thickness = outerR * 0.28;
    final midR = outerR - thickness / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final ringRect = Rect.fromCircle(center: center, radius: midR);

    canvas.drawCircle(
      center,
      midR,
      Paint()
        ..color = trackColor
        ..strokeWidth = thickness
        ..style = PaintingStyle.stroke,
    );

    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi;
      final isHi = i == highlightedIndex;
      final dim = highlightedIndex != null && !isHi;
      final stroke = isHi ? thickness * 1.15 : thickness;
      final color = dim
          ? colors[i % colors.length].withValues(alpha: 0.45)
          : colors[i % colors.length];
      final paint = Paint()
        ..color = color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;
      canvas.drawArc(ringRect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.trackColor != trackColor ||
      old.highlightedIndex != highlightedIndex;
}

