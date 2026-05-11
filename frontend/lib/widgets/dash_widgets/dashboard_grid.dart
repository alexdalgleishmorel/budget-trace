import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';

/// Absolute-positioned drag/resize grid. Each widget occupies a rectangle
/// in grid units (`layout.x`, `y`, `w`, `h`); the grid converts to pixel
/// rects via its current column count and per-cell row height.
///
/// Drag and resize are always available — a drag handle on the title area
/// moves the whole widget, and a corner handle bottom-right resizes.
/// Both snap to grid on release; collisions just overdraw, since this
/// matches the free-form Datadog dashboard behaviour the user asked for.
class DashboardGrid extends StatefulWidget {
  const DashboardGrid({
    super.key,
    required this.widgets,
    required this.columns,
    required this.rowHeight,
    required this.minSizes,
    required this.builder,
    required this.onLayoutChanged,
  });

  final List<DashboardWidget> widgets;
  final int columns;
  final double rowHeight;
  final Map<String, WidgetLayout> minSizes;

  /// Build the body of one widget (we wrap it with chrome ourselves).
  final Widget Function(BuildContext, DashboardWidget) builder;

  /// Fires when the user finishes a drag or resize. Receives the new full
  /// layout list (id → new layout). Caller is expected to PUT the layout
  /// to the backend.
  final void Function(Map<int, WidgetLayout>) onLayoutChanged;

  @override
  State<DashboardGrid> createState() => _DashboardGridState();
}

class _DashboardGridState extends State<DashboardGrid> {
  /// Local overrides applied during a drag/resize. Committed to
  /// `onLayoutChanged` on release.
  final Map<int, WidgetLayout> _local = {};

  /// True from gesture start until release. Drives the snap-grid overlay
  /// so it only appears while the user is actively moving something.
  bool _dragging = false;

  WidgetLayout _layoutFor(DashboardWidget w) =>
      _local[w.id] ?? w.layout;

  WidgetLayout _minFor(String type) =>
      widget.minSizes[type] ?? const WidgetLayout(x: 0, y: 0, w: 2, h: 2);

  int get _rows {
    var maxRow = 0;
    for (final w in widget.widgets) {
      final l = _layoutFor(w);
      final bottom = l.y + l.h;
      if (bottom > maxRow) maxRow = bottom;
    }
    // Leave one empty row at the bottom so dropping a new widget feels
    // natural (and the grid never collapses to zero height).
    return math.max(maxRow + 2, 6);
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return LayoutBuilder(
      builder: (_, c) {
        final cellW = c.maxWidth / widget.columns;
        final totalH = _rows * widget.rowHeight;
        return SingleChildScrollView(
          child: SizedBox(
            height: totalH,
            child: Stack(
              children: [
                // Snap-grid overlay only appears while a gesture is in
                // progress — keeps the dashboard clean at rest.
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GridPainter(
                          columns: widget.columns,
                          rowHeight: widget.rowHeight,
                          rows: _rows,
                          color: bt.ruleSoft,
                        ),
                      ),
                    ),
                  ),
                for (final w in widget.widgets)
                  _positionedTile(context, w, cellW),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _positionedTile(BuildContext context, DashboardWidget w, double cellW) {
    final layout = _layoutFor(w);
    final left = layout.x * cellW;
    final top = layout.y * widget.rowHeight;
    final width = layout.w * cellW;
    final height = layout.h * widget.rowHeight;
    return AnimatedPositioned(
      key: ValueKey('pos-${w.id}'),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      left: left, top: top,
      width: width, height: height,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: _TileContainer(
          onDragUpdate: (dx, dy) => _onDragUpdate(w, dx, dy, cellW),
          onDragStart: _onGestureStart,
          onResizeUpdate: (dx, dy) => _onResizeUpdate(w, dx, dy, cellW),
          onResizeStart: _onGestureStart,
          onEnd: _commit,
          child: widget.builder(context, w),
        ),
      ),
    );
  }

  void _onGestureStart() {
    if (!_dragging) setState(() => _dragging = true);
  }

  /// Live drag — `dx`/`dy` are the cumulative pixel delta from the gesture
  /// start. We always recompute against the widget's *original* layout so
  /// rounding errors don't accumulate over a long drag.
  void _onDragUpdate(DashboardWidget w, double dx, double dy, double cellW) {
    final base = w.layout;
    // `math.max(0, …)` so the clamp upper bound is never negative — which
    // it would be if a widget is wider than the current column count (e.g.
    // a 3-wide tile on a 2-column mobile grid). `clamp` throws when the
    // lower bound exceeds the upper bound.
    final maxX = math.max(0, widget.columns - base.w);
    final newX = (base.x + (dx / cellW).round()).clamp(0, maxX);
    final newY = math.max(0, base.y + (dy / widget.rowHeight).round());
    setState(() {
      _local[w.id] = base.copyWith(x: newX, y: newY);
    });
  }

  void _onResizeUpdate(DashboardWidget w, double dx, double dy, double cellW) {
    final base = w.layout;
    final min = _minFor(w.type);
    final addW = (dx / cellW).round();
    final addH = (dy / widget.rowHeight).round();
    // Defensive: if base.x leaves less room than `min.w`, cap the lower
    // bound at the available space so the clamp never throws. The widget
    // can still be made taller in that scenario, just not wider.
    final maxW = math.max(1, widget.columns - base.x);
    final loW = math.min(min.w, maxW);
    final newW = (base.w + addW).clamp(loW, maxW);
    final newH = math.max(min.h, base.h + addH);
    setState(() {
      _local[w.id] = base.copyWith(w: newW, h: newH);
    });
  }

  /// Commit on gesture end. Crucially, this does **not** recompute the
  /// layout from any delta — it just pushes whatever the most recent
  /// `_onDragUpdate` / `_onResizeUpdate` produced. The previous version
  /// passed `(0, 0)` deltas on end, which the resolver mistook for
  /// "snap back to origin".
  void _commit() {
    setState(() => _dragging = false);
    if (_local.isEmpty) return;
    widget.onLayoutChanged(Map.of(_local));
    setState(() => _local.clear());
  }
}

/// Holds the visual frame and exposes drag / resize gesture hit areas.
/// Drag and resize are always active — the grid no longer has an "edit
/// mode" toggle.
class _TileContainer extends StatelessWidget {
  const _TileContainer({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onEnd,
    required this.child,
  });

  final VoidCallback onDragStart;
  final void Function(double dx, double dy) onDragUpdate;
  final VoidCallback onResizeStart;
  final void Function(double dx, double dy) onResizeUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        // Move handle — overlays the top edge so titlebar buttons keep
        // working (they sit above this in the stack).
        Positioned(
          left: 0, right: 60, top: 0, height: 28,
          child: _DragHandle(
            cursor: SystemMouseCursors.grab,
            onStart: onDragStart,
            onUpdate: onDragUpdate,
            onEnd: onEnd,
          ),
        ),
        // Resize handle bottom-right.
        Positioned(
          right: 0, bottom: 0, width: 22, height: 22,
          child: _DragHandle(
            cursor: SystemMouseCursors.resizeDownRight,
            onStart: onResizeStart,
            onUpdate: onResizeUpdate,
            onEnd: onEnd,
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: bt.surface2,
                border: Border.all(color: bt.ruleStrong),
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(10),
                  topLeft: Radius.circular(6),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.south_east, size: 12, color: bt.ink3),
            ),
          ),
        ),
      ],
    );
  }
}

class _DragHandle extends StatefulWidget {
  const _DragHandle({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.cursor,
    this.child,
  });

  final VoidCallback onStart;

  /// Live updates with the cumulative pan delta from the gesture start.
  final void Function(double dx, double dy) onUpdate;

  /// Called once on release / cancel. The grid commits whatever the last
  /// `onUpdate` produced; this callback intentionally carries no delta so
  /// the receiver can't accidentally interpret release as "no movement".
  final VoidCallback onEnd;

  final MouseCursor cursor;
  final Widget? child;

  @override
  State<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<_DragHandle> {
  Offset _origin = Offset.zero;

  @override
  Widget build(BuildContext context) {
    // `translucent` so taps still reach widgets layered below (e.g. the
    // titlebar's refresh / edit / delete buttons). The pan recognizer
    // here only claims the gesture once the pointer moves past the
    // standard threshold, which is what we want — quick clicks belong to
    // the icon buttons.
    return MouseRegion(
      cursor: widget.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (d) {
          _origin = d.globalPosition;
          widget.onStart();
        },
        onPanUpdate: (d) {
          final delta = d.globalPosition - _origin;
          widget.onUpdate(delta.dx, delta.dy);
        },
        onPanEnd: (_) => widget.onEnd(),
        onPanCancel: widget.onEnd,
        child: widget.child ?? const SizedBox.expand(),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.columns,
    required this.rowHeight,
    required this.rows,
    required this.color,
  });

  final int columns;
  final double rowHeight;
  final int rows;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final cellW = size.width / columns;
    for (var c = 1; c < columns; c++) {
      final x = c * cellW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var r = 1; r < rows; r++) {
      final y = r * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.columns != columns ||
      old.rowHeight != rowHeight ||
      old.rows != rows ||
      old.color != color;
}
