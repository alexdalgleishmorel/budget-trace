import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One labelled row inside a [ChartHoverTooltip]. Used per slice (pie),
/// per series (timeseries), or as a single line (treemap-style summary).
class ChartTooltipLine {
  const ChartTooltipLine({
    this.swatchColor,
    required this.label,
    required this.value,
    this.trailing,
  });

  /// Optional coloured square to the left of the label. When non-null,
  /// disambiguates which series/slice the row refers to.
  final Color? swatchColor;
  final String label;
  final String value;
  /// Optional trailing string — pct% for pie/treemap, or unit suffix.
  final String? trailing;
}

/// Dark glass card used by the pie / timeseries / treemap charts to surface
/// extra detail on hover. Sized to its content — render inside a Positioned
/// inside a Stack with the chart.
class ChartHoverTooltip extends StatelessWidget {
  const ChartHoverTooltip({
    super.key,
    required this.lines,
    this.header,
  });

  /// Optional header line (e.g. the x-axis label / date on a timeseries).
  final String? header;
  final List<ChartTooltipLine> lines;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6101830),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 16,
            spreadRadius: -2,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null) ...[
              Text(
                header!,
                style: TextStyle(
                  fontSize: 10,
                  color: bt.ink3.withValues(alpha: 0.85),
                  letterSpacing: 0.06 * 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
            ],
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 3),
              _Line(line: lines[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line});
  final ChartTooltipLine line;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (line.swatchColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: line.swatchColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              line.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            line.value,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (line.trailing != null) ...[
            const SizedBox(width: 6),
            Text(
              line.trailing!,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xCCFFFFFF),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Position [child] near [cursor] inside a [containerSize] without spilling
/// off the edges. Approximates the child size with [estimatedWidth] /
/// [estimatedHeight]; passing realistic estimates avoids occasional flicker
/// at the edges as the tooltip grows from row to row.
class PositionedChartTooltip extends StatelessWidget {
  const PositionedChartTooltip({
    super.key,
    required this.cursor,
    required this.containerSize,
    required this.child,
    this.estimatedWidth = 200,
    this.estimatedHeight = 64,
    this.gap = 12,
  });

  final Offset cursor;
  final Size containerSize;
  final Widget child;
  final double estimatedWidth;
  final double estimatedHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    // Default to top-right of cursor; flip horizontally / vertically if
    // that'd spill over the chart bounds.
    var left = cursor.dx + gap;
    var top = cursor.dy - estimatedHeight - gap;
    if (left + estimatedWidth > containerSize.width) {
      left = cursor.dx - estimatedWidth - gap;
    }
    if (top < 0) {
      top = cursor.dy + gap;
    }
    left = left.clamp(0.0, math.max(0.0, containerSize.width - estimatedWidth));
    top = top.clamp(0.0, math.max(0.0, containerSize.height - estimatedHeight));
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(child: child),
    );
  }
}
