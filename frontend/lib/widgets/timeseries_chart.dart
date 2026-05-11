import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'budget_card.dart';

// ── Public API ───────────────────────────────────────────────────────────────

/// A single data point. `x` is unitless to the widget — typically a day index,
/// week number, or any monotonically-increasing scalar the caller picks.
class ChartPoint {
  const ChartPoint(this.x, this.y);
  final double x;
  final double y;
}

enum LineStyle { solid, dashed }

/// One line on the chart. Use [LineStyle.dashed] for AI-projected forecasts —
/// the widget enforces nothing semantic, but that's the convention.
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.points,
    this.style = LineStyle.solid,
    this.color,
  });

  final String label;
  final List<ChartPoint> points;
  final LineStyle style;

  /// When null the chart picks a colour from a theme-derived palette.
  final Color? color;
}

/// Generic line chart with auto-scaled axes, multiple series, and a forecast
/// (dashed) line style. Designed to be driven by AI-generated insight specs:
/// give it a title, a list of [ChartSeries], and it renders.
///
/// `height` is optional: when null, the chart flexes to fill its parent's
/// remaining vertical space. Pass an explicit value for fixed-height use
/// (e.g. inside scrollable lists like the Insights transcript).
class TimeseriesChart extends StatelessWidget {
  const TimeseriesChart({
    super.key,
    required this.title,
    required this.series,
    this.xAxisLabel,
    this.yAxisLabel,
    this.xTickLabels,
    this.height,
    this.showTitle = true,
  });

  final String title;
  final List<ChartSeries> series;
  final String? xAxisLabel;
  final String? yAxisLabel;

  /// Optional human-readable tick labels along the x-axis. When provided,
  /// these replace the numeric endpoint labels — first label sits at xMin,
  /// last at xMax, others evenly spaced between.
  final List<String>? xTickLabels;

  /// Null = flex to fill parent (use inside a sized box / Expanded).
  /// Non-null = fixed height (use inside scroll views).
  final double? height;

  /// When false, the chart drops its own title row. Used inside a
  /// `WidgetCard` where the chrome's titlebar already shows the title.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final palette = _palette(bt);
    final coloured = List<ChartSeries>.generate(series.length, (i) {
      final s = series[i];
      return s.color != null
          ? s
          : ChartSeries(
              label: s.label,
              points: s.points,
              style: s.style,
              color: palette[i % palette.length],
            );
    });

    final painter = CustomPaint(
      painter: _ChartPainter(
        series: coloured,
        bt: bt,
        xTickLabels: xTickLabels,
      ),
      size: Size.infinite,
    );

    return BudgetCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle)
              Text(title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: bt.ink,
                  )),
            if (yAxisLabel != null) ...[
              if (showTitle) const SizedBox(height: 2),
              BudgetLabel(yAxisLabel!),
            ],
            if (showTitle || yAxisLabel != null) const SizedBox(height: 10),
            if (height != null)
              SizedBox(height: height, child: painter)
            else
              Expanded(child: painter),
            if (xAxisLabel != null) ...[
              const SizedBox(height: 4),
              Center(child: BudgetLabel(xAxisLabel!)),
            ],
            if (coloured.length > 1) ...[
              const SizedBox(height: 10),
              _Legend(series: coloured, bt: bt),
            ],
          ],
        ),
      ),
    );
  }

  static List<Color> _palette(BudgetTheme bt) =>
      [bt.ink, bt.pos, bt.warn, bt.neg, bt.ink3];
}

// ── Legend ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend({required this.series, required this.bt});
  final List<ChartSeries> series;
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: series.map((s) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(18, 2),
              painter: _SwatchPainter(color: s.color!, style: s.style),
            ),
            const SizedBox(width: 6),
            Text(s.label,
                style: TextStyle(fontSize: 11.5, color: bt.ink3)),
          ],
        );
      }).toList(),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter({required this.color, required this.style});
  final Color color;
  final LineStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round;
    if (style == LineStyle.dashed) {
      _drawDashed(canvas, Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint, 3, 2);
    } else {
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.style != style;
}

// ── Painter ──────────────────────────────────────────────────────────────────

const double _padL = 38.0;
const double _padR = 10.0;
const double _padT = 4.0;
const double _padB = 18.0;

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.series,
    required this.bt,
    this.xTickLabels,
  });

  final List<ChartSeries> series;
  final BudgetTheme bt;
  final List<String>? xTickLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final innerW = size.width - _padL - _padR;
    final innerH = size.height - _padT - _padB;
    if (innerW <= 0 || innerH <= 0) return;

    final allPoints = series.expand((s) => s.points).toList();
    if (allPoints.isEmpty) {
      _drawEmpty(canvas, size);
      return;
    }

    var xMin = allPoints.first.x;
    var xMax = allPoints.first.x;
    var yMin = 0.0; // anchor y axis at zero — usually what a viewer expects
    var yMax = allPoints.first.y;
    for (final p in allPoints) {
      if (p.x < xMin) xMin = p.x;
      if (p.x > xMax) xMax = p.x;
      if (p.y > yMax) yMax = p.y;
      if (p.y < yMin) yMin = p.y;
    }
    if (xMax == xMin) xMax = xMin + 1;
    if (yMax == yMin) yMax = yMin + 1;
    // Pad the top of the y range so the highest point isn't flush with the frame.
    yMax += (yMax - yMin) * 0.1;

    double xAt(double v) => _padL + ((v - xMin) / (xMax - xMin)) * innerW;
    double yAt(double v) => _padT + (1 - (v - yMin) / (yMax - yMin)) * innerH;

    // Grid + y-axis labels at 0%, 50%, 100%.
    final gridPaint = Paint()
      ..color = bt.rule
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      fontSize: 9, fontFamily: 'monospace', color: bt.ink4,
    );
    for (final f in [0.0, 0.5, 1.0]) {
      final yVal = yMin + (yMax - yMin) * f;
      final y = yAt(yVal);
      canvas.drawLine(Offset(_padL, y), Offset(_padL + innerW, y), gridPaint);
      _drawText(canvas, _fmtAxis(yVal),
          Offset(_padL - 4, y - 5), labelStyle, TextAlign.right);
    }

    // X-axis labels: explicit ticks if supplied (thinned to whatever fits
    // the available width without overlap), otherwise just the numeric
    // endpoints.
    final ticks = xTickLabels;
    if (ticks != null && ticks.isNotEmpty) {
      final n = ticks.length;

      // Measure the widest label so we can compute how many fit. A small
      // gap keeps adjacent labels visually separated.
      double maxLabelWidth = 0;
      for (final label in ticks) {
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        if (tp.width > maxLabelWidth) maxLabelWidth = tp.width;
      }
      const labelGap = 12.0;
      final slot = maxLabelWidth + labelGap;
      final maxLabels = slot > 0 ? (innerW / slot).floor() : n;
      // Stride between rendered labels; always show first + last when
      // there's room for at least two.
      final stride = maxLabels <= 1 ? n : ((n - 1) / (maxLabels - 1)).ceil().clamp(1, n);

      final drawn = <int>{};
      for (var i = 0; i < n; i += stride) {
        drawn.add(i);
      }
      drawn.add(n - 1); // ensure the final label is always drawn

      for (final i in drawn) {
        final t = n == 1 ? 0.5 : i / (n - 1);
        final x = _padL + t * innerW;
        final align = i == 0
            ? TextAlign.left
            : (i == n - 1 ? TextAlign.right : TextAlign.center);
        _drawText(canvas, ticks[i],
            Offset(x, size.height - 5), labelStyle, align);
      }
    } else {
      _drawText(canvas, _fmtAxis(xMin),
          Offset(_padL, size.height - 5), labelStyle, TextAlign.left);
      _drawText(canvas, _fmtAxis(xMax),
          Offset(_padL + innerW, size.height - 5), labelStyle, TextAlign.right);
    }

    // Each series.
    for (final s in series) {
      if (s.points.length < 2) continue;
      final paint = Paint()
        ..color = s.color!
        ..strokeWidth = 1.75
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final pts = [for (final p in s.points) Offset(xAt(p.x), yAt(p.y))];
      if (s.style == LineStyle.dashed) {
        for (int i = 1; i < pts.length; i++) {
          _drawDashed(canvas, pts[i - 1], pts[i], paint, 4, 4);
        }
      } else {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        canvas.drawPath(path, paint);
      }

      // End dot for solid lines (helps the eye track where observed data ends).
      if (s.style == LineStyle.solid && pts.isNotEmpty) {
        canvas.drawCircle(pts.last, 3, Paint()..color = s.color!);
      }
    }
  }

  void _drawEmpty(Canvas canvas, Size size) {
    _drawText(
      canvas,
      'No data',
      Offset(size.width / 2, size.height / 2),
      TextStyle(fontSize: 11, color: bt.ink4),
      TextAlign.center,
    );
  }

  String _fmtAxis(double v) {
    if (v.abs() >= 1000) return fmtMoney(v);
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style,
      TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => -tp.width,
      TextAlign.center => -tp.width / 2,
      _ => 0.0,
    };
    tp.paint(canvas, Offset(pos.dx + dx, pos.dy));
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.series != series || old.xTickLabels != xTickLabels;
}

// Shared dashed-line walker — used by both the legend swatch and the painter.
void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint,
    double on, double off) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final len = sqrt(dx * dx + dy * dy);
  if (len == 0) return;
  final ux = dx / len, uy = dy / len;
  double dist = 0;
  bool drawing = true;
  while (dist < len) {
    final seg = drawing ? on : off;
    final end = min(dist + seg, len);
    if (drawing) {
      canvas.drawLine(
        Offset(a.dx + ux * dist, a.dy + uy * dist),
        Offset(a.dx + ux * end, a.dy + uy * end),
        paint,
      );
    }
    dist = end;
    drawing = !drawing;
  }
}
