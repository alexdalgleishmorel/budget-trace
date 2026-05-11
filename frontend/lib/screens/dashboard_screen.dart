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
  List<DashboardSummary>? _allDashboards;
  WidgetMetricRegistry? _registry;
  List<SavedInsight>? _savedInsights;
  // Category paths fetched once at load — feed the drawer's category-path
  // dropdown. Includes the synthetic "Unknown" path (= uncategorised).
  List<String> _categoryPaths = const [];
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
        widget.client.list(),
        widget.client.listMetrics(),
        widget.client.listSavedInsights(),
        _categoriesClient.list(),
      ]);
      if (!mounted) return;
      final cats = (results[4] as List<CategoryDto>);
      // Backend "Unknown" path is overloaded to mean "uncategorised
      // transactions"; the categories endpoint returns it as a regular row
      // with `isUnknown=true`. Drop other system rows, surface the rest in
      // their natural tree order.
      final paths = cats.map((c) => c.path).toList();
      setState(() {
        _dashboard = results[0] as Dashboard;
        _allDashboards = results[1] as List<DashboardSummary>;
        _registry = results[2] as WidgetMetricRegistry;
        _savedInsights = results[3] as List<SavedInsight>;
        _categoryPaths = paths;
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

  Future<void> _switchTo(int id) async {
    if (id == _id) return;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => DashboardScreen(client: widget.client, dashboardId: id),
    ));
  }

  Future<void> _rename() async {
    final current = _dashboard?.name ?? '';
    final next = await _promptName(
        context, title: 'Rename dashboard', initial: current);
    if (next == null || next.isEmpty || next == current) return;
    try {
      await widget.client.update(_id, name: next);
      if (mounted) await _refreshDashboard();
    } catch (e) {
      if (!mounted) return;
      _showError('Rename failed: $e');
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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete dashboard?'),
        content: Text('“${_dashboard?.name ?? ''}” and all its widgets will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client.delete(_id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showError('Delete failed: $e');
    }
  }

  Future<void> _addWidget({DashboardWidget? existing}) async {
    final registry = _registry;
    if (registry == null) return;
    final saved = _savedInsights ?? const [];
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
          savedInsights: saved,
          categoryPaths: _categoryPaths,
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
                    all: _allDashboards ?? const [],
                    presets: _registry?.timeRangePresets ?? const [],
                    onSwitch: _switchTo,
                    onRename: _rename,
                    onDelete: _delete,
                    onAdd: () => _addWidget(),
                    onBack: () => Navigator.of(context).pop(),
                    onTimeRangeChanged: _setTimeRange,
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
    required this.all,
    required this.presets,
    required this.onSwitch,
    required this.onRename,
    required this.onDelete,
    required this.onAdd,
    required this.onBack,
    required this.onTimeRangeChanged,
  });

  final Dashboard dashboard;
  final List<DashboardSummary> all;
  final List<String> presets;
  final void Function(int) onSwitch;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onAdd;
  final VoidCallback onBack;
  final void Function(DashboardTimeRange) onTimeRangeChanged;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onBack,
              tooltip: 'All dashboards',
              icon: BudgetIcons.build('chevron-left', size: 18, color: bt.ink2),
            ),
            PopupMenuButton<_HeaderAction>(
              offset: const Offset(0, 36),
              tooltip: 'Switch dashboard',
              itemBuilder: (_) {
                return [
                  for (final d in all)
                    PopupMenuItem<_HeaderAction>(
                      value: _HeaderAction.switchTo(d.id),
                      child: Row(
                        children: [
                          if (d.id == dashboard.id)
                            BudgetIcons.build('check',
                                size: 14, color: bt.ink2)
                          else
                            const SizedBox(width: 14),
                          const SizedBox(width: 8),
                          Expanded(child: Text(d.name)),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _HeaderAction.rename(),
                    child: Text('Rename…'),
                  ),
                  PopupMenuItem(
                    value: const _HeaderAction.deleteDashboard(),
                    child: Text('Delete dashboard',
                        style: TextStyle(color: bt.neg)),
                  ),
                ];
              },
              onSelected: (a) {
                switch (a.kind) {
                  case 'switch':
                    onSwitch(a.dashboardId!);
                  case 'rename':
                    onRename();
                  case 'delete':
                    onDelete();
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      dashboard.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.02,
                        color: bt.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  BudgetIcons.build('chevron-down', size: 16, color: bt.ink3),
                ],
              ),
            ),
          ],
        ),
        _TimeRangePicker(
          presets: presets,
          current: dashboard.timeRange,
          onChanged: onTimeRangeChanged,
        ),
        FilledButton.icon(
          onPressed: onAdd,
          icon: BudgetIcons.build('plus', size: 14, color: bt.bg),
          label: const Text('Add widget'),
        ),
      ],
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
  });

  final List<String> presets;
  final DashboardTimeRange current;
  final void Function(DashboardTimeRange) onChanged;

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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bt.surface,
          border: Border.all(color: bt.ruleStrong),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 14, color: bt.ink3),
            const SizedBox(width: 6),
            Text(
              _labelFor(current),
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: bt.ink2,
              ),
            ),
            const SizedBox(width: 4),
            BudgetIcons.build('chevron-down', size: 14, color: bt.ink3),
          ],
        ),
      ),
    );
  }
}

class _HeaderAction {
  const _HeaderAction.switchTo(int id)
      : kind = 'switch',
        dashboardId = id;
  const _HeaderAction.rename()
      : kind = 'rename',
        dashboardId = null;
  const _HeaderAction.deleteDashboard()
      : kind = 'delete',
        dashboardId = null;

  final String kind;
  final int? dashboardId;
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
              'Add a widget to start visualizing. You can pick from curated '
              'metrics or use insights you saved from the Insights tab.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: bt.ink4, height: 1.5),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: BudgetIcons.build('plus', size: 14, color: bt.bg),
              label: const Text('Add widget'),
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

Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
}
