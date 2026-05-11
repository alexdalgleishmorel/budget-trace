import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../services/dashboards_client.dart';
import '../../theme/app_theme.dart';
import 'widget_card.dart';

/// Drawer used both to add a new widget and to edit an existing one. Flow:
/// pick widget type → pick data source (curated metric or saved insight)
/// → fill any per-widget knobs. Live preview pulled from the backend on
/// a debounce.
///
/// Per the dashboard-level time range, this drawer **does not** collect
/// `start` / `end` dates — those live on the dashboard.
class AddWidgetDrawer extends StatefulWidget {
  const AddWidgetDrawer({
    super.key,
    required this.dashboardId,
    required this.client,
    required this.registry,
    required this.savedInsights,
    required this.categoryPaths,
    this.initial,
  });

  final int dashboardId;
  final DashboardsClient client;
  final WidgetMetricRegistry registry;
  final List<SavedInsight> savedInsights;

  /// Full set of category paths the user can pick from when a metric's
  /// params include a `category_path` field. Loaded by the caller from
  /// `GET /categories` so the dropdown stays in sync with the user's tree.
  final List<String> categoryPaths;

  final DashboardWidget? initial;

  @override
  State<AddWidgetDrawer> createState() => _AddWidgetDrawerState();
}

class _AddWidgetDrawerState extends State<AddWidgetDrawer> {
  static const _types = [
    ('timeseries', 'Time series'),
    ('bar', 'Bar'),
    ('pie', 'Pie'),
    ('query_value', 'Big number'),
    ('table', 'Table'),
    ('treemap', 'Treemap'),
  ];

  /// User-facing one-liner shown when a widget type is selected. Tells the
  /// user *what* the widget renders and *when* to reach for it.
  static const _typeDescriptions = <String, String>{
    'timeseries':
        'A line chart over time. Best for spotting trends and seasonality — '
        'monthly spend across the last year, weekly grocery costs, etc.',
    'bar':
        'Horizontal bars ranked by value. Best when you want to compare buckets '
        'side-by-side — categories, weeks, or top merchants.',
    'pie':
        'Donut chart with one slice per group, with a total in the centre. '
        'Best when you want to see how a total breaks down across a small '
        'number of categories.',
    'query_value':
        'A single headline number, with an optional delta versus the previous '
        'period. Best for KPIs you want at a glance — total spend, average '
        'per month, transaction count.',
    'table':
        'A data table with columns. Best for surfacing rows of detail — '
        'recent transactions, top merchants with multiple metrics.',
    'treemap':
        'Nested rectangles sized by value. Best when you have many categories '
        'and want to compare them by area without crowding a pie chart.',
  };

  String? _type;
  String _sourceKind = 'metric'; // 'metric' | 'insight'
  String? _metricId;
  int? _insightId;
  late Map<String, dynamic> _params;
  final TextEditingController _titleCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  int _previewTick = 0;
  WidgetData? _previewData;
  bool _previewBusy = false;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    _params = {};
    final init = widget.initial;
    if (init != null) {
      _type = init.type;
      _sourceKind = init.dataSource.kind;
      _metricId = init.dataSource.metricId;
      _insightId = init.dataSource.insightId;
      _params = Map.of(init.dataSource.params);
      _titleCtrl.text = init.title;
      _schedulePreview();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.initial != null;

  List<WidgetMetricDef> get _compatibleMetrics =>
      _type == null
          ? const []
          : widget.registry.metrics
              .where((m) => m.widgetTypes.contains(_type))
              .toList();

  WidgetMetricDef? get _selectedMetric =>
      _metricId == null ? null : _compatibleMetrics.where((m) => m.id == _metricId).cast<WidgetMetricDef?>().firstWhere((_) => true, orElse: () => null);

  SavedInsight? get _selectedInsight => _insightId == null
      ? null
      : widget.savedInsights
          .where((s) => s.id == _insightId)
          .cast<SavedInsight?>()
          .firstWhere((_) => true, orElse: () => null);

  /// Saved insights compatible with the chosen widget type. Each saved
  /// insight has a fixed type (whatever the AI produced), so the drawer
  /// can only attach an insight whose type matches the user's choice.
  List<SavedInsight> get _compatibleInsights => _type == null
      ? const []
      : widget.savedInsights.where((s) => s.widget.type == _type).toList();

  bool get _insightCompatible => _compatibleInsights.isNotEmpty;

  bool get _canSave =>
      _type != null &&
      ((_sourceKind == 'metric' && _metricId != null) ||
          (_sourceKind == 'insight' && _insightId != null));

  /// Resolves the actual title we'll send. Empty input falls back to the
  /// metric label / saved-insight title, so the user can leave Title blank.
  String _resolvedTitle() {
    final v = _titleCtrl.text.trim();
    if (v.isNotEmpty) return v;
    if (_sourceKind == 'metric' && _selectedMetric != null) {
      return _selectedMetric!.label;
    }
    if (_sourceKind == 'insight' && _selectedInsight != null) {
      return _selectedInsight!.title;
    }
    return 'Untitled';
  }

  void _onTypeSelected(String t) {
    setState(() {
      _type = t;
      if (_sourceKind == 'metric' && _metricId != null) {
        final still = widget.registry.metrics
            .any((m) => m.id == _metricId && m.widgetTypes.contains(t));
        if (!still) _metricId = null;
      }
      if (_sourceKind == 'insight' && !_insightCompatible) {
        _sourceKind = 'metric';
        _insightId = null;
      }
      _previewData = null;
    });
    _schedulePreview();
  }

  void _onMetricSelected(String id) {
    setState(() {
      _metricId = id;
      _params = {};
      final def = widget.registry.metrics.firstWhere((m) => m.id == id);
      for (final p in def.paramsSchema) {
        if (p['default'] != null) _params[p['name'] as String] = p['default'];
      }
    });
    _schedulePreview();
  }

  void _onParamChanged(String name, dynamic value) {
    setState(() => _params[name] = value);
    _schedulePreview();
  }

  Future<void> _schedulePreview() async {
    final myTick = ++_previewTick;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || myTick != _previewTick) return;
    if (!_canSave) return;
    setState(() {
      _previewBusy = true;
      _previewError = null;
    });
    try {
      final dataSource = _sourceKind == 'metric'
          ? WidgetDataSource.metric(metricId: _metricId!, params: _params)
          : WidgetDataSource.insight(insightId: _insightId!);
      // Create a draft widget so we can hit GET /data through the normal
      // path — then delete it. The dashboard briefly shows an extra
      // widget; preview is debounced and short-lived.
      final draft = await widget.client.createWidget(
        widget.dashboardId,
        type: _type!,
        title: '__preview__',
        layout: _minLayout(_type!),
        dataSource: dataSource,
      );
      try {
        final data = await widget.client
            .getWidgetData(widget.dashboardId, draft.id);
        if (!mounted || myTick != _previewTick) return;
        setState(() => _previewData = data);
      } finally {
        try {
          await widget.client.deleteWidget(widget.dashboardId, draft.id);
        } catch (_) {/* preview cleanup is best-effort */}
      }
    } catch (e) {
      if (!mounted || myTick != _previewTick) return;
      setState(() => _previewError = e.toString());
    } finally {
      if (mounted && myTick == _previewTick) {
        setState(() => _previewBusy = false);
      }
    }
  }

  WidgetLayout _minLayout(String type) {
    final min = widget.registry.minSizes[type];
    return WidgetLayout(x: 0, y: 0, w: min?.w ?? 2, h: min?.h ?? 2);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ds = _sourceKind == 'metric'
          ? WidgetDataSource.metric(metricId: _metricId!, params: _params)
          : WidgetDataSource.insight(insightId: _insightId!);
      final title = _resolvedTitle();
      DashboardWidget result;
      if (_isEdit) {
        result = await widget.client.updateWidget(
          widget.dashboardId, widget.initial!.id,
          title: title,
          dataSource: ds,
        );
      } else {
        result = await widget.client.createWidget(
          widget.dashboardId,
          type: _type!,
          title: title,
          layout: _minLayout(_type!),
          dataSource: ds,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(result);
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
    return Material(
      color: bt.bg,
      child: SafeArea(
        child: Column(
          children: [
            _Header(
              title: _isEdit ? 'Edit widget' : 'Add widget',
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionLabel('Preview'),
                  const SizedBox(height: 8),
                  _PreviewArea(
                    type: _type,
                    title: _resolvedTitle(),
                    data: _previewData,
                    busy: _previewBusy,
                    error: _previewError,
                  ),
                  const SizedBox(height: 20),
                  if (!_isEdit) _typePicker(bt),
                  if (_type != null) ...[
                    if (!_isEdit) const SizedBox(height: 20),
                    _SectionLabel('Title'),
                    const SizedBox(height: 8),
                    _titleField(bt),
                    const SizedBox(height: 20),
                    _sourcePicker(bt),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(fontSize: 12, color: bt.neg)),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: bt.rule)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: !_canSave || _busy ? null : _save,
                      child: Text(_isEdit ? 'Save' : 'Add widget'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typePicker(BudgetTheme bt) {
    final description =
        _type == null ? null : _typeDescriptions[_type!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Widget type'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _types)
              _TypeChip(
                label: t.$2,
                id: t.$1,
                selected: _type == t.$1,
                onTap: () => _onTypeSelected(t.$1),
              ),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: bt.surface2,
              border: Border.all(color: bt.ruleSoft),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
            child: Text(
              description,
              style: TextStyle(fontSize: 12, color: bt.ink3, height: 1.45),
            ),
          ),
        ],
      ],
    );
  }

  Widget _titleField(BudgetTheme bt) {
    final fallback = (_sourceKind == 'metric' && _selectedMetric != null)
        ? _selectedMetric!.label
        : (_sourceKind == 'insight' && _selectedInsight != null
            ? _selectedInsight!.title
            : 'Untitled');
    return TextField(
      controller: _titleCtrl,
      decoration: InputDecoration(
        hintText: 'Optional — defaults to “$fallback”',
        hintStyle: TextStyle(color: bt.ink5, fontStyle: FontStyle.italic),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _sourcePicker(BudgetTheme bt) {
    final selectionDescription = _sourceKind == 'metric'
        ? 'Curated, live aggregations computed from your transactions on every '
          'load. Use a metric when you want fresh numbers as your data changes.'
        : 'A frozen snapshot you saved from an Insights chat. The chart is '
          'stored as-is and re-renders without running the AI again. Use a '
          'saved insight to keep a specific finding pinned to your dashboard.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Data source'),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            const ButtonSegment(value: 'metric', label: Text('Metric')),
            ButtonSegment(
              value: 'insight',
              label: Text(
                  _insightCompatible ? 'Saved insight' : 'Saved insight (n/a)'),
              enabled: _insightCompatible,
            ),
          ],
          selected: {_sourceKind},
          onSelectionChanged: (s) => setState(() {
            _sourceKind = s.first;
            _previewData = null;
            _schedulePreview();
          }),
        ),
        const SizedBox(height: 8),
        Text(
          selectionDescription,
          style: TextStyle(fontSize: 11, color: bt.ink4, height: 1.45),
        ),
        const SizedBox(height: 12),
        if (_sourceKind == 'metric') _metricForm(bt) else _insightPicker(bt),
      ],
    );
  }

  Widget _metricForm(BudgetTheme bt) {
    final metrics = _compatibleMetrics;
    if (metrics.isEmpty) {
      return Text(
        'No metrics support this widget type.',
        style: TextStyle(fontSize: 12, color: bt.ink4),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _metricId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Metric', isDense: true,
          ),
          // Each item shows a label + a faded one-liner description so the
          // user can compare metrics without leaving the dropdown.
          items: [
            for (final m in metrics)
              DropdownMenuItem(
                value: m.id,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.label,
                          style: TextStyle(
                              fontSize: 13, color: bt.ink,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(
                        m.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: bt.ink4, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          // Closed-state shows just the label — the description is
          // already visible inline in the help text below.
          selectedItemBuilder: (_) => [
            for (final m in metrics)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(m.label,
                    style: TextStyle(fontSize: 13, color: bt.ink)),
              ),
          ],
          onChanged: (v) {
            if (v != null) _onMetricSelected(v);
          },
        ),
        if (_metricId != null) ...[
          const SizedBox(height: 8),
          Text(
            metrics.firstWhere((m) => m.id == _metricId).description,
            style: TextStyle(fontSize: 11, color: bt.ink4, height: 1.45),
          ),
          if (!metrics.firstWhere((m) => m.id == _metricId).usesTimeRange) ...[
            const SizedBox(height: 6),
            Text(
              'Note: this metric ignores the dashboard\'s time range.',
              style: TextStyle(
                fontSize: 11, color: bt.warn, fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _ParamsForm(
            schema: metrics.firstWhere((m) => m.id == _metricId).paramsSchema,
            params: _params,
            categoryPaths: widget.categoryPaths,
            onChanged: _onParamChanged,
          ),
        ],
      ],
    );
  }

  Widget _insightPicker(BudgetTheme bt) {
    final compatible = _compatibleInsights;
    if (compatible.isEmpty) {
      // Either no saved insights at all, or none match the chosen type.
      final msg = widget.savedInsights.isEmpty
          ? 'No saved insights yet. Save one from the Insights tab to use it here.'
          : 'No saved insights of this widget type. Save one from the '
              'Insights tab (the AI picks the type) or switch to a different '
              'widget type above.';
      return Text(msg, style: TextStyle(fontSize: 12, color: bt.ink4));
    }
    return DropdownButtonFormField<int>(
      initialValue: _insightId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Saved insight', isDense: true,
      ),
      items: [
        for (final s in compatible)
          DropdownMenuItem(value: s.id, child: Text(s.title)),
      ],
      onChanged: (v) {
        setState(() => _insightId = v);
        _schedulePreview();
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.12 * 10.5,
        color: context.bt.ink4,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: bt.rule)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: bt.ink,
              )),
        ),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close, size: 18)),
      ]),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Material(
      color: selected ? bt.ink : bt.surface,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            border: Border.all(color: selected ? bt.ink : bt.ruleStrong),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? bt.bg : bt.ink2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ParamsForm extends StatelessWidget {
  const _ParamsForm({
    required this.schema,
    required this.params,
    required this.categoryPaths,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> schema;
  final Map<String, dynamic> params;
  final List<String> categoryPaths;
  final void Function(String name, dynamic value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in schema)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ParamField(
              field: field,
              value: params[field['name']],
              categoryPaths: categoryPaths,
              onChanged: (v) => onChanged(field['name'] as String, v),
            ),
          ),
      ],
    );
  }
}

class _ParamField extends StatelessWidget {
  const _ParamField({
    required this.field,
    required this.value,
    required this.categoryPaths,
    required this.onChanged,
  });

  final Map<String, dynamic> field;
  final dynamic value;
  final List<String> categoryPaths;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final type = field['type'] as String;
    final label = field['label'] as String;
    final desc = field['description'] as String?;

    Widget control;
    switch (type) {
      case 'enum':
        control = DropdownButtonFormField<String>(
          initialValue: value as String? ?? field['default'] as String?,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            for (final o in (field['options'] as List).cast<String>())
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: onChanged,
        );
      case 'category_path':
        // `null` = no filter (all categories). Keeping the dropdown
        // null-safe with a discriminated entry up top.
        final current = (value as String?)?.trim();
        final knownValue =
            current != null && categoryPaths.contains(current) ? current : null;
        control = DropdownButtonFormField<String?>(
          initialValue: knownValue,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('All categories',
                  style: TextStyle(color: bt.ink3, fontStyle: FontStyle.italic)),
            ),
            for (final p in categoryPaths)
              DropdownMenuItem<String?>(value: p, child: Text(p)),
          ],
          onChanged: onChanged,
        );
      case 'int':
        control = TextFormField(
          initialValue: '${value ?? field['default'] ?? ''}',
          decoration: InputDecoration(labelText: label, isDense: true),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) onChanged(n);
          },
        );
      case 'bool':
        control = SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: (value as bool?) ?? (field['default'] as bool? ?? false),
          onChanged: onChanged,
        );
      default:
        return const SizedBox.shrink();
    }

    if (desc == null || desc.isEmpty) return control;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        control,
        const SizedBox(height: 4),
        Text(desc, style: TextStyle(fontSize: 11, color: bt.ink4)),
      ],
    );
  }
}

class _PreviewArea extends StatelessWidget {
  const _PreviewArea({
    required this.type,
    required this.title,
    required this.data,
    required this.busy,
    required this.error,
  });

  final String? type;
  final String title;
  final WidgetData? data;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: bt.bg2,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: bt.rule),
      ),
      padding: const EdgeInsets.all(8),
      child: type == null
          ? Center(
              child: Text('Pick a widget type to preview',
                  style: TextStyle(fontSize: 12, color: bt.ink4)))
          : (data == null
              ? Center(
                  child: busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          error == null
                              ? 'Fill the form to see a preview'
                              : 'Preview unavailable: $error',
                          style: TextStyle(fontSize: 12, color: bt.ink4),
                          textAlign: TextAlign.center,
                        ),
                )
              : _PreviewWidgetCard(type: type!, title: title, data: data!)),
    );
  }
}

class _PreviewWidgetCard extends StatelessWidget {
  const _PreviewWidgetCard({
    required this.type,
    required this.title,
    required this.data,
  });
  final String type;
  final String title;
  final WidgetData data;

  @override
  Widget build(BuildContext context) {
    final fake = DashboardWidget(
      id: -1, dashboardId: -1, type: type, title: title,
      layout: const WidgetLayout(x: 0, y: 0, w: 4, h: 3),
      dataSource: const WidgetDataSource.metric(metricId: 'preview'),
      config: const {},
      createdAt: '', updatedAt: '',
    );
    return WidgetCard(
      widget: fake,
      previewData: data,
    );
  }
}
