import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Squarified-ish treemap. Lays children out in stripes alternating
/// horizontal/vertical, scaling each rectangle by its share of the
/// remaining area. Cheap to compute, looks tidy at typical card sizes.
class TreemapWidgetBody extends StatelessWidget {
  const TreemapWidgetBody({super.key, required this.data});
  final WidgetData data;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final raw = (data.data['nodes'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((n) => (n['value'] as num).toDouble() > 0)
        .toList();
    if (raw.isEmpty) {
      return Center(
        child: Text('No data',
            style: TextStyle(fontSize: 12, color: bt.ink4)),
      );
    }
    raw.sort((a, b) =>
        (b['value'] as num).toDouble().compareTo((a['value'] as num).toDouble()));

    // Use the Arctic category palette — every entry is saturated mid-dark
    // enough that pure-white text stays readable.
    final palette = bt.categoryColors;

    final grandTotal =
        raw.fold<double>(0, (a, n) => a + (n['value'] as num).toDouble());

    return LayoutBuilder(
      builder: (_, c) {
        final rects = _layout(
          raw, Rect.fromLTWH(0, 0, c.maxWidth, c.maxHeight),
        );
        return Stack(
          children: [
            for (var i = 0; i < rects.length; i++)
              Positioned.fromRect(
                rect: rects[i].$2,
                child: _TreemapTile(
                  label: rects[i].$1['label'] as String,
                  value: (rects[i].$1['value'] as num).toDouble(),
                  total: grandTotal,
                  color: palette[i % palette.length],
                  border: bt.glassBorder,
                  rect: rects[i].$2,
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Tile widget (with hover tooltip) ───────────────────────────────────

  /// Simple stripe layout: split the longest side first, take items in
  /// descending order, allocate area proportional to value.
  List<(Map<String, dynamic>, Rect)> _layout(
    List<Map<String, dynamic>> items,
    Rect area,
  ) {
    final out = <(Map<String, dynamic>, Rect)>[];
    var remaining = area;
    var total = items.fold<double>(
        0, (a, n) => a + (n['value'] as num).toDouble());
    for (var i = 0; i < items.length; i++) {
      final v = (items[i]['value'] as num).toDouble();
      if (i == items.length - 1) {
        out.add((items[i], remaining));
        break;
      }
      final frac = total == 0 ? 0.0 : v / total;
      if (remaining.width >= remaining.height) {
        final w = remaining.width * frac;
        out.add((items[i],
            Rect.fromLTWH(remaining.left, remaining.top, w, remaining.height)));
        remaining = Rect.fromLTWH(
            remaining.left + w, remaining.top,
            remaining.width - w, remaining.height);
      } else {
        final h = remaining.height * frac;
        out.add((items[i],
            Rect.fromLTWH(remaining.left, remaining.top, remaining.width, h)));
        remaining = Rect.fromLTWH(
            remaining.left, remaining.top + h,
            remaining.width, remaining.height - h);
      }
      total -= v;
    }
    return out;
  }
}

class _TreemapTile extends StatelessWidget {
  const _TreemapTile({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
    required this.border,
    required this.rect,
  });

  final String label;
  final double value;
  final double total;
  final Color color;
  final Color border;
  final Rect rect;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (value / total) * 100 : 0.0;
    final tooltip =
        '$label\n\$${fmtMoneyDecimal(value)}   ${pct.toStringAsFixed(1)}%';

    final tile = Container(
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: border, width: 2),
      ),
      padding: const EdgeInsets.all(6),
      child: rect.height < 32 || rect.width < 56
          ? const SizedBox.shrink()
          : DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '\$${fmtMoneyDecimal(value)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
    );

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 200),
      preferBelow: false,
      textStyle: const TextStyle(
        fontSize: 11,
        color: Colors.white,
        height: 1.35,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      decoration: BoxDecoration(
        color: const Color(0xE6101830),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 14,
            spreadRadius: -2,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: tile,
    );
  }
}
