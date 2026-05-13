import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../services/dashboards_client.dart';
import '../../theme/app_theme.dart';
import '../cat_icon.dart';
import '../glass.dart';
import 'bar_widget.dart';
import 'pie_widget.dart';
import 'query_value_widget.dart';
import 'recent_table_widget.dart';
import 'timeseries_widget.dart';
import 'treemap_widget.dart';

/// Outer chrome for any widget on a dashboard: titlebar, body, edit /
/// delete affordances, refresh button, and loading / error / empty states.
/// The body delegates to a type-specific renderer below.
class WidgetCard extends StatefulWidget {
  const WidgetCard({
    super.key,
    required this.widget,
    this.client,
    this.onEdit,
    this.onDelete,
    this.previewData,
    this.compact = false,
    this.revalidationKey,
  }) : assert(client != null || previewData != null,
            'Either a client (to fetch data) or previewData must be provided.');

  final DashboardWidget widget;
  final DashboardsClient? client;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// When non-null, the card renders this data instead of fetching. Used by
  /// the Add-widget drawer preview where the widget hasn't been persisted yet.
  final WidgetData? previewData;

  /// Drop the titlebar padding for drawer previews where space is tight.
  final bool compact;

  /// External key that, when changed, forces a re-fetch. The dashboard
  /// passes its time-range cache key so every widget refreshes when the
  /// range shifts. Unrelated to widget identity (which is captured
  /// separately via `widget.updatedAt`).
  final String? revalidationKey;

  @override
  State<WidgetCard> createState() => _WidgetCardState();
}

class _WidgetCardState extends State<WidgetCard> {
  WidgetData? _data;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.previewData != null) {
      _data = widget.previewData;
    } else {
      _refresh();
    }
  }

  @override
  void didUpdateWidget(WidgetCard old) {
    super.didUpdateWidget(old);
    if (widget.previewData != null && widget.previewData != _data) {
      setState(() => _data = widget.previewData);
    }
    final identityChanged = old.widget.id != widget.widget.id ||
        old.widget.updatedAt != widget.widget.updatedAt;
    final revalidated = old.revalidationKey != widget.revalidationKey;
    if (widget.previewData == null && (identityChanged || revalidated)) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (widget.previewData != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client!
          .getWidgetData(widget.widget.dashboardId, widget.widget.id);
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return GlassSurface(
      tier: GlassTier.t1,
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.compact)
            _Titlebar(
              title: widget.widget.title,
              busy: _busy,
              isSnapshot: _data?.isSnapshot ?? false,
              onRefresh: _refresh,
              onEdit: widget.onEdit,
              onDelete: widget.onDelete,
            ),
          Expanded(child: _body(bt)),
          if (!widget.compact && (_data?.viaChat ?? false))
            _ViaChatFooter(bt: bt),
        ],
      ),
    );
  }

  Widget _body(BudgetTheme bt) {
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _refresh);
    }
    if (_data == null) {
      return const Center(
        child: SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: _renderBody(_data!, widget.widget.type),
    );
  }
}

Widget _renderBody(WidgetData data, String type) {
  switch (type) {
    case 'timeseries':
      return TimeseriesWidgetBody(data: data);
    case 'bar':
      return BarWidgetBody(data: data);
    case 'pie':
      return PieWidgetBody(data: data);
    case 'query_value':
      return QueryValueWidgetBody(data: data);
    case 'table':
      return RecentTableWidgetBody(data: data);
    case 'treemap':
      return TreemapWidgetBody(data: data);
  }
  return Center(child: Text('Unknown widget type: $type'));
}

class _Titlebar extends StatelessWidget {
  const _Titlebar({
    required this.title,
    required this.busy,
    required this.isSnapshot,
    required this.onRefresh,
    this.onEdit,
    this.onDelete,
  });

  /// Display string formatted server-side as `{Widget type} : {Metric}`
  /// (or `… : Snapshot`). Empty means the chrome should render no title
  /// — used by the chat transcript where the surrounding text already
  /// labels the widget.
  final String title;
  final bool busy;

  /// True when the underlying widget is a frozen snapshot — shows a small
  /// "Snapshot" badge and disables the refresh icon (there's nothing to
  /// refresh; the bytes are stored as-is and don't track the dashboard's
  /// time range).
  final bool isSnapshot;

  final VoidCallback onRefresh;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final hasTitle = title.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: bt.ruleSoft)),
      ),
      child: Row(
        children: [
          if (hasTitle)
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: bt.ink2,
                ),
              ),
            )
          else
            const Spacer(),
          if (isSnapshot) ...[
            _SnapshotChip(bt: bt),
            const SizedBox(width: 4),
          ],
          if (busy) ...[
            SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(bt.ink4),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (!isSnapshot)
            _IconBtn(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 16),
              onPressed: onRefresh,
            ),
          if (onEdit != null)
            _IconBtn(
              tooltip: 'Edit',
              icon: BudgetIcons.build('edit', size: 14, strokeWidth: 1.6,
                  color: context.bt.ink3),
              onPressed: onEdit,
            ),
          if (onDelete != null)
            _IconBtn(
              tooltip: 'Delete',
              icon: BudgetIcons.build('trash', size: 14, strokeWidth: 1.6,
                  color: context.bt.neg),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// Subtle footer that tags widgets added via the Insights chat
/// "Save to dashboard…" flow. Uses the same green accent the rest of
/// the AI surface uses (`bt.pos`).
class _ViaChatFooter extends StatelessWidget {
  const _ViaChatFooter({required this.bt});
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      alignment: Alignment.centerLeft,
      child: Text(
        'Added from Insights',
        style: TextStyle(
          fontSize: 10,
          color: bt.pos,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}


class _SnapshotChip extends StatelessWidget {
  const _SnapshotChip({required this.bt});
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          "Captured from a chat answer — data is frozen and doesn't follow the "
          "dashboard's time range.",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bt.surface2,
          border: Border.all(color: bt.ruleSoft),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Text(
          'Snapshot',
          style: TextStyle(
            fontSize: 10,
            color: bt.ink3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: IconTheme(
            data: IconThemeData(color: context.bt.ink3, size: 16),
            child: icon,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: bt.ink2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: bt.ink4),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: bt.ruleStrong),
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
                child: Text('Retry',
                    style: TextStyle(
                        fontSize: 11, color: bt.ink2,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
