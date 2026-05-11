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

    // Curated, opaque palette where every entry pairs with white text at
    // a usable contrast ratio. Avoids the lighter `tile*` swatches so the
    // text contrast doesn't depend on per-tile luminance heuristics.
    final palette = _treemapPalette(bt);

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
                child: Container(
                  decoration: BoxDecoration(
                    color: palette[i % palette.length],
                    border: Border.all(color: bt.surface, width: 2),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: rects[i].$2.height < 32 || rects[i].$2.width < 56
                      ? const SizedBox.shrink()
                      : DefaultTextStyle(
                          // Every palette colour is dark enough that
                          // pure-white text is legible on it. A soft
                          // shadow guarantees readability even on the
                          // lightest entries.
                          style: TextStyle(
                            color: Colors.white,
                            shadows: const [
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
                                rects[i].$1['label'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '\$${fmtMoneyDecimal(
                                  (rects[i].$1['value'] as num).toDouble(),
                                )}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontFeatures: [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// All entries are saturated mid-to-dark colours so pure-white text with
  /// a soft drop shadow stays readable everywhere.
  static List<Color> _treemapPalette(BudgetTheme bt) {
    return [
      const Color(0xFF2E5C8A), // deep blue
      const Color(0xFF2E7D53), // bt.pos-aligned green
      const Color(0xFFB4432F), // bt.neg red
      const Color(0xFF8A5A2E), // saddle brown
      const Color(0xFF6C3E8A), // purple
      const Color(0xFF267C7C), // teal
      const Color(0xFF9A7A2C), // bt.warn ochre
      const Color(0xFF3D5749), // forest
    ];
  }

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
