import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../services/categories_client.dart';
import '../../services/dashboards_client.dart';
import '../../theme/app_theme.dart';
import 'widget_card.dart';

/// Drawer used both to add a new widget and to edit an existing one. Flow:
/// pick widget type → pick a curated metric → fill its params. Live
/// preview pulled from the backend on a debounce.
///
/// The drawer only creates `kind:"metric"` widgets. Snapshot widgets are
/// created exclusively by the "Save to dashboard…" flow on the Insights
/// chat — there's no path to build one here.
///
/// Per the dashboard-level time range, this drawer **does not** collect
/// `start` / `end` dates — those live on the dashboard.
class AddWidgetDrawer extends StatefulWidget {
  const AddWidgetDrawer({
    super.key,
    required this.dashboardId,
    required this.client,
    required this.registry,
    required this.categories,
    this.initial,
  });

  final int dashboardId;
  final DashboardsClient client;
  final WidgetMetricRegistry registry;

  /// Full set of categories the user can pick from when a metric's params
  /// include a `category_path` field. The full DTO is passed (rather than
  /// just paths) so the drawer can honour each schema field's
  /// `parent_only` flag — drill-down params filter out leaves.
  final List<CategoryDto> categories;

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
  String? _metricId;
  late Map<String, dynamic> _params;
  bool _busy = false;
  String? _error;

  /// Title is creation-locked — created widgets get the server-derived
  /// `{Type} : {Metric}` title. Editing exposes a rename field;
  /// `_titleCtrl` is only instantiated then. `_initialTitle` is what
  /// was pre-filled when the drawer opened; if the user didn't touch
  /// it we send empty on save so the server re-derives (so e.g.
  /// changing the rollup period refreshes the title too).
  TextEditingController? _titleCtrl;
  String? _initialTitle;

  /// Set when editing an existing snapshot widget. Snapshots are
  /// frozen — only the title is editable.
  bool _editingSnapshot = false;

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
      _editingSnapshot = init.dataSource.isSnapshot;
      _metricId = init.dataSource.metricId;
      _params = Map.of(init.dataSource.params);
      _titleCtrl = TextEditingController(text: init.title);
      _initialTitle = init.title;
      _schedulePreview();
    }
  }

  @override
  void dispose() {
    _titleCtrl?.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.initial != null;

  List<WidgetMetricDef> get _compatibleMetrics =>
      _type == null
          ? const []
          : widget.registry.metrics
              .where((m) => m.widgetTypes.contains(_type))
              .toList();

  bool get _canSave {
    if (_type == null) return false;
    // Snapshot widgets can still be retitled in edit mode — that's the
    // only thing exposed for them.
    if (_editingSnapshot) return _isEdit;
    return _metricId != null;
  }

  void _onTypeSelected(String t) {
    setState(() {
      _type = t;
      if (_metricId != null) {
        final still = widget.registry.metrics
            .any((m) => m.id == _metricId && m.widgetTypes.contains(t));
        if (!still) _metricId = null;
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
    if (_editingSnapshot) {
      // Snapshots can't be re-resolved through the create-and-fetch
      // dance; preview is read straight from the existing widget.
      if (widget.initial != null) {
        try {
          final data = await widget.client.getWidgetData(
            widget.dashboardId, widget.initial!.id,
          );
          if (!mounted || myTick != _previewTick) return;
          setState(() => _previewData = data);
        } catch (e) {
          if (!mounted || myTick != _previewTick) return;
          setState(() => _previewError = e.toString());
        } finally {
          if (mounted && myTick == _previewTick) {
            setState(() => _previewBusy = false);
          }
        }
      }
      return;
    }
    try {
      final dataSource =
          WidgetDataSource.metric(metricId: _metricId!, params: _params);
      // Create a draft widget so we can hit GET /data through the normal
      // path — then delete it. The dashboard briefly shows an extra
      // widget; preview is debounced and short-lived.
      final draft = await widget.client.createWidget(
        widget.dashboardId,
        type: _type!,
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

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      DashboardWidget result;
      if (_isEdit) {
        // If the user didn't touch the title field, send empty so the
        // backend re-derives — that way changing the metric or its
        // rollup period also refreshes the title. If they typed a
        // rename, send it verbatim.
        final typed = _titleCtrl?.text.trim() ?? '';
        final untouched = typed == (_initialTitle ?? '').trim();
        final titleToSend = untouched ? '' : typed;
        result = await widget.client.updateWidget(
          widget.dashboardId, widget.initial!.id,
          title: titleToSend,
          dataSource: _editingSnapshot
              ? null
              : WidgetDataSource.metric(metricId: _metricId!, params: _params),
        );
      } else {
        result = await widget.client.createWidget(
          widget.dashboardId,
          type: _type!,
          dataSource:
              WidgetDataSource.metric(metricId: _metricId!, params: _params),
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
                    data: _previewData,
                    busy: _previewBusy,
                    error: _previewError,
                  ),
                  const SizedBox(height: 20),
                  if (!_isEdit) _typePicker(bt),
                  if (_type != null) ...[
                    if (!_isEdit) const SizedBox(height: 20),
                    if (_isEdit) ...[
                      _SectionLabel('Title'),
                      const SizedBox(height: 8),
                      _titleField(bt),
                      const SizedBox(height: 20),
                    ],
                    if (_editingSnapshot)
                      _SnapshotBanner(bt: bt)
                    else
                      _metricForm(bt),
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
    return TextField(
      controller: _titleCtrl,
      decoration: const InputDecoration(
        hintText: 'Leave blank to use the auto-derived title',
        isDense: true,
      ),
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
            categories: widget.categories,
            onChanged: _onParamChanged,
          ),
        ],
      ],
    );
  }

}

/// Banner shown when "editing" a snapshot widget. Snapshots are frozen
/// end-to-end — there's nothing to change here. To get fresh data, add
/// a curated-metric widget instead.
class _SnapshotBanner extends StatelessWidget {
  const _SnapshotBanner({required this.bt});
  final BudgetTheme bt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bt.warnBg,
        border: Border.all(color: bt.warn),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        'Snapshot widget — data is frozen and ignores the dashboard\'s '
        'time range. To get fresh data, add a curated-metric widget '
        'instead.',
        style: TextStyle(fontSize: 12, color: bt.ink3, height: 1.45),
      ),
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
    required this.categories,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> schema;
  final Map<String, dynamic> params;
  final List<CategoryDto> categories;
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
              categories: categories,
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
    required this.categories,
    required this.onChanged,
  });

  final Map<String, dynamic> field;
  final dynamic value;
  final List<CategoryDto> categories;
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
              DropdownMenuItem(value: o, child: Text(_humanise(o))),
          ],
          onChanged: onChanged,
        );
      case 'category_path':
        // `null` = no filter (all categories). When the schema marks
        // the field as `parent_only` (drill-down targets), the list is
        // filtered to non-leaf categories — picking a leaf has no
        // children to drill into.
        final parentOnly = field['parent_only'] == true;
        final visible = [
          for (final c in categories)
            if (!c.isUnknown && (!parentOnly || !c.isLeaf)) c,
        ];
        final placeholder =
            parentOnly ? 'Top-level breakdown' : 'All categories';
        final current = (value as String?)?.trim();
        final knownValue = current != null &&
                visible.any((c) => c.path == current)
            ? current
            : null;
        control = DropdownButtonFormField<String?>(
          initialValue: knownValue,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(placeholder,
                  style: TextStyle(color: bt.ink3, fontStyle: FontStyle.italic)),
            ),
            for (final c in visible)
              DropdownMenuItem<String?>(value: c.path, child: Text(c.path)),
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

  /// Turn a wire-format enum value into the dropdown label. Backend stores
  /// lowercase `snake_case` (e.g. `previous_period`, `trailing_avg`) so
  /// resolvers can match exactly; we display them as `Previous period`,
  /// `Trailing avg`.
  static String _humanise(String value) {
    if (value.isEmpty) return value;
    final spaced = value.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

class _PreviewArea extends StatelessWidget {
  const _PreviewArea({
    required this.type,
    required this.data,
    required this.busy,
    required this.error,
  });

  final String? type;
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
              : _PreviewWidgetCard(type: type!, data: data!)),
    );
  }
}

class _PreviewWidgetCard extends StatelessWidget {
  const _PreviewWidgetCard({
    required this.type,
    required this.data,
  });
  final String type;
  final WidgetData data;

  @override
  Widget build(BuildContext context) {
    final fake = DashboardWidget(
      id: -1, dashboardId: -1, type: type, title: '',
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
