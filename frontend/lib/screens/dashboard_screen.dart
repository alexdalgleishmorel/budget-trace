import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../services/categories_client.dart';
import '../services/dashboards_client.dart';
import '../theme/app_theme.dart';
import '../widgets/cat_icon.dart';
import '../widgets/dash_widgets/add_widget_drawer.dart';
import '../widgets/dash_widgets/dashboard_grid.dart';
import '../widgets/dash_widgets/widget_card.dart';
import '../widgets/glass.dart';

/// One dashboard, full-screen. Owns the loaded dashboard, the edit-mode
/// toggle, the dashboard-switcher dropdown, and the add-widget drawer.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.client,
    required this.dashboardId,
  });

  final DashboardsClient client;
  final int dashboardId;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final CategoriesClient _categoriesClient = CategoriesClient();

  Dashboard? _dashboard;
  WidgetMetricRegistry? _registry;
  // Category rows fetched once at load — feed the drawer's category
  // dropdown. Drawer filters out the synthetic "Unknown" path and (for
  // drill-down params) any leaf categories using `isUnknown` / `isLeaf`.
  List<CategoryDto> _categories = const [];
  String? _error;

  Timer? _layoutDebounce;

  int get _id => _dashboard?.id ?? widget.dashboardId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _layoutDebounce?.cancel();
    _categoriesClient.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait([
        widget.client.get(widget.dashboardId),
        widget.client.listMetrics(),
        _categoriesClient.list(),
      ]);
      if (!mounted) return;
      final cats = (results[2] as List<CategoryDto>);
      setState(() {
        _dashboard = results[0] as Dashboard;
        _registry = results[1] as WidgetMetricRegistry;
        _categories = cats;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _refreshDashboard() async {
    try {
      final fresh = await widget.client.get(widget.dashboardId);
      if (mounted) setState(() => _dashboard = fresh);
    } catch (_) {
      // Silent — the existing widgets remain rendered.
    }
  }

  Future<void> _setTimeRange(DashboardTimeRange next) async {
    try {
      await widget.client.update(_id, timeRange: next);
      if (mounted) await _refreshDashboard();
    } catch (e) {
      if (!mounted) return;
      _showError('Could not update time range: $e');
    }
  }

  Future<void> _addWidget({DashboardWidget? existing}) async {
    final registry = _registry;
    if (registry == null) return;
    final result = await showModalBottomSheet<DashboardWidget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.bt.bg,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: AddWidgetDrawer(
          dashboardId: _id,
          client: widget.client,
          registry: registry,
          categories: _categories,
          initial: existing,
        ),
      ),
    );
    if (result != null) {
      await _refreshDashboard();
    }
  }

  Future<void> _deleteWidget(DashboardWidget w) async {
    try {
      await widget.client.deleteWidget(_id, w.id);
      if (mounted) await _refreshDashboard();
    } catch (e) {
      if (!mounted) return;
      _showError('Could not delete widget: $e');
    }
  }

  void _onLayoutChanged(Map<int, WidgetLayout> updates) {
    // Optimistic update — patch the in-memory list, debounce the server PUT.
    final dash = _dashboard;
    if (dash == null) return;
    final next = [
      for (final w in dash.widgets)
        updates.containsKey(w.id)
            ? w.copyWith(layout: updates[w.id])
            : w,
    ];
    setState(() {
      _dashboard = Dashboard(
        id: dash.id, name: dash.name,
        timeRange: dash.timeRange,
        createdAt: dash.createdAt, updatedAt: dash.updatedAt,
        widgets: next,
      );
    });
    _layoutDebounce?.cancel();
    _layoutDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        await widget.client.putLayout(_id, [
          for (final w in next)
            (id: w.id, layout: w.layout),
        ]);
      } catch (e) {
        if (!mounted) return;
        _showError('Could not save layout: $e');
        // Re-fetch authoritative state on failure.
        _refreshDashboard();
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Widgets')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load dashboard',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: bt.ink)),
                const SizedBox(height: 6),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: bt.ink4)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _loadAll, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    final dash = _dashboard;
    if (dash == null) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: bt.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, c) {
            final isDesktop = c.maxWidth >= 600;
            const desktopColumns = 6;
            const desktopRowHeight = 90.0;
            final padding = isDesktop
                ? const EdgeInsets.fromLTRB(28, 16, 28, 16)
                : const EdgeInsets.fromLTRB(12, 8, 12, 8);
            return Column(
              children: [
                Padding(
                  padding: padding,
                  child: _Header(
                    dashboard: dash,
                    presets: _registry?.timeRangePresets ?? const [],
                    onAdd: () => _addWidget(),
                    onBack: () => Navigator.of(context).pop(),
                    onTimeRangeChanged: _setTimeRange,
                    isDesktop: isDesktop,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: padding.horizontal / 2),
                    child: dash.widgets.isEmpty
                        ? _EmptyDashboard(onAdd: () => _addWidget())
                        : (isDesktop
                            ? DashboardGrid(
                                widgets: dash.widgets,
                                columns: desktopColumns,
                                rowHeight: desktopRowHeight,
                                minSizes:
                                    _registry?.minSizes ?? const {},
                                onLayoutChanged: _onLayoutChanged,
                                builder: (_, w) => WidgetCard(
                                  widget: w,
                                  client: widget.client,
                                  onEdit: () => _addWidget(existing: w),
                                  onDelete: () => _deleteWidget(w),
                                  revalidationKey:
                                      dash.timeRange.cacheKey,
                                ),
                              )
                            : _MobileDashboardList(
                                widgets: dash.widgets,
                                client: widget.client,
                                revalidationKey: dash.timeRange.cacheKey,
                                onEdit: (w) =>
                                    _addWidget(existing: w),
                                onDelete: _deleteWidget,
                              )),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.dashboard,
    required this.presets,
    required this.onAdd,
    required this.onBack,
    required this.onTimeRangeChanged,
    required this.isDesktop,
  });

  final Dashboard dashboard;
  final List<String> presets;
  final VoidCallback onAdd;
  final VoidCallback onBack;
  final void Function(DashboardTimeRange) onTimeRangeChanged;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;

    if (!isDesktop) {
      // Mobile: tight icon row — back chevron, spacer, calendar pill
      // (opens the same PopupMenuButton), accent-gradient + pill. The
      // labelled desktop variants overflowed on narrow widths.
      return Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'All dashboards',
            icon: BudgetIcons.build(
                'chevron-left', size: 18, color: bt.ink2),
          ),
          const Spacer(),
          _TimeRangePicker(
            presets: presets,
            current: dashboard.timeRange,
            onChanged: onTimeRangeChanged,
            compact: true,
          ),
          const SizedBox(width: 6),
          _AddWidgetIconButton(onPressed: onAdd),
        ],
      );
    }

    // Desktop: back left, time picker right, "Add widget" visually centred.
    // The Stack lets the centred button ignore the asymmetric widths of the
    // side controls so it sits at the true horizontal centre.
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: 'All dashboards',
              icon: BudgetIcons.build(
                  'chevron-left', size: 18, color: bt.ink2),
            ),
            const Spacer(),
            _TimeRangePicker(
              presets: presets,
              current: dashboard.timeRange,
              onChanged: onTimeRangeChanged,
            ),
          ],
        ),
        GlassButton(
          label: 'Add widget',
          onPressed: onAdd,
          variant: GlassButtonVariant.primary,
          icon: BudgetIcons.build('plus', size: 14, strokeWidth: 1.8),
        ),
      ],
    );
  }
}

/// 36×36 accent-gradient pill used in the mobile header for "Add widget".
/// Matches the new-chat / send-message buttons on the Insights tab.
class _AddWidgetIconButton extends StatelessWidget {
  const _AddWidgetIconButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Tooltip(
      message: 'Add widget',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bt.accentGrad,
                stops: bt.accentGradStops,
              ),
              boxShadow: [
                BoxShadow(
                  color: bt.accent.withValues(alpha: 0.28),
                  blurRadius: 14,
                  spreadRadius: -3,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: BudgetIcons.build('plus',
                size: 14, strokeWidth: 2, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Compact preset picker for the dashboard's time range. "Custom" opens a
/// date-range dialog. All widgets on the dashboard react automatically via
/// their `revalidationKey`.
class _TimeRangePicker extends StatelessWidget {
  const _TimeRangePicker({
    required this.presets,
    required this.current,
    required this.onChanged,
    this.compact = false,
  });

  final List<String> presets;
  final DashboardTimeRange current;
  final void Function(DashboardTimeRange) onChanged;
  /// When true, render as a 36×36 round glass pill with just the calendar
  /// icon. Used in the mobile header where the labelled variant overflows.
  final bool compact;

  static const _labels = <String, String>{
    'last_30_days': 'Last 30 days',
    'last_3_months': 'Last 3 months',
    'last_6_months': 'Last 6 months',
    'last_12_months': 'Last 12 months',
    'month_to_date': 'Month to date',
    'year_to_date': 'Year to date',
    'all_time': 'All time',
    'custom': 'Custom…',
  };

  String _labelFor(DashboardTimeRange tr) {
    if (tr.preset == 'custom' && tr.customStart != null && tr.customEnd != null) {
      return '${tr.customStart} → ${tr.customEnd}';
    }
    return _labels[tr.preset] ?? tr.preset;
  }

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final available = presets.isEmpty ? _labels.keys.toList() : presets;
    return PopupMenuButton<String>(
      offset: const Offset(0, 36),
      tooltip: 'Time range',
      itemBuilder: (_) => [
        for (final p in available)
          CheckedPopupMenuItem(
            value: p,
            checked: current.preset == p,
            child: Text(_labels[p] ?? p),
          ),
      ],
      onSelected: (p) async {
        if (p == 'custom') {
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2010),
            lastDate: DateTime.now().add(const Duration(days: 1)),
            initialDateRange: current.preset == 'custom' &&
                    current.customStart != null && current.customEnd != null
                ? DateTimeRange(
                    start: DateTime.parse(current.customStart!),
                    end: DateTime.parse(current.customEnd!),
                  )
                : null,
          );
          if (picked == null) return;
          onChanged(DashboardTimeRange(
            preset: 'custom',
            customStart: picked.start.toIso8601String().substring(0, 10),
            customEnd: picked.end.toIso8601String().substring(0, 10),
          ));
        } else {
          onChanged(DashboardTimeRange(preset: p));
        }
      },
      child: compact
          ? Tooltip(
              message: _labelFor(current),
              child: SizedBox(
                width: 36,
                height: 36,
                child: GlassSurface(
                  tier: GlassTier.t2,
                  radius: 999,
                  elevated: false,
                  sheen: false,
                  child: Center(
                    child: Icon(Icons.calendar_today_outlined,
                        size: 14, color: bt.ink2),
                  ),
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bt.fieldBg,
                border: Border.all(color: bt.fieldBorder),
                borderRadius: const BorderRadius.all(Radius.circular(10)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14, color: bt.ink3),
                  const SizedBox(width: 6),
                  Text(
                    _labelFor(current),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: bt.ink2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  BudgetIcons.build('chevron-down',
                      size: 14, color: bt.ink3),
                ],
              ),
            ),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BudgetIcons.build('grid', size: 26, color: bt.ink4),
            const SizedBox(height: 12),
            Text('Empty dashboard',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: bt.ink)),
            const SizedBox(height: 6),
            Text(
              'Add a widget to start visualizing — pick from the curated '
              'metrics, or save one from the Insights tab.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: bt.ink4, height: 1.5),
            ),
            const SizedBox(height: 14),
            GlassButton(
              label: 'Add widget',
              onPressed: onAdd,
              variant: GlassButtonVariant.primary,
              icon: BudgetIcons.build('plus', size: 14, strokeWidth: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobile rendering for a dashboard's widgets. Always one column, fixed
/// per-tile height, ordered by creation time — drag/resize live only on
/// the desktop grid since arranging tiles by touch on a small screen is
/// fiddly and adds little value when there's only room for one column.
class _MobileDashboardList extends StatelessWidget {
  const _MobileDashboardList({
    required this.widgets,
    required this.client,
    required this.revalidationKey,
    required this.onEdit,
    required this.onDelete,
  });

  final List<DashboardWidget> widgets;
  final DashboardsClient client;
  final String revalidationKey;
  final void Function(DashboardWidget) onEdit;
  final void Function(DashboardWidget) onDelete;

  /// Single default height for every widget on mobile. Tall enough for
  /// the timeseries / table widgets to breathe, short enough that the
  /// big-number widget doesn't feel empty.
  static const _tileHeight = 260.0;

  @override
  Widget build(BuildContext context) {
    // Stable order: ascending by creation time, so newly-added widgets
    // append to the bottom of the list without shuffling the rest.
    final ordered = [...widgets]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final w = ordered[i];
        return SizedBox(
          height: _tileHeight,
          child: WidgetCard(
            widget: w,
            client: client,
            onEdit: () => onEdit(w),
            onDelete: () => onDelete(w),
            revalidationKey: revalidationKey,
          ),
        );
      },
    );
  }
}

