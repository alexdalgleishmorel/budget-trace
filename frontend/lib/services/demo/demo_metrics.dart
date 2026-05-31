/// Dart port of the backend's `services/widget_metrics.py` resolvers and the
/// `mcp_server.py` aggregation helpers, operating over the in-memory demo data
/// instead of SQLite. Pure functions: given the category + transaction lists
/// and a metric request, return the exact `data` dict the widget renderers
/// expect — identical in shape to `GET /dashboards/:id/widgets/:wid/data`.
///
/// Only reachable in the demo build; never imported by the normal app.
library;

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Fixed "today" for the demo. The seed data ends 2026-04-30; pinning the clock
/// here means rolling time-range presets (`last_3_months`, …) always frame the
/// sample data no matter when the demo is loaded.
DateTime demoToday() => DateTime(2026, 4, 30);

double _round2(num v) => (v * 100).round() / 100;

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _parse(String iso) => DateTime.parse(iso);

// ── Time-range resolution (mirrors resolve_time_range) ───────────────────────

const String _allTimeStart = '2000-01-01';

(String, String) resolveTimeRange(
  String? preset, [
  String? customStart,
  String? customEnd,
]) {
  final today = demoToday();
  final p = (preset == null || preset.isEmpty) ? 'last_3_months' : preset;
  switch (p) {
    case 'custom':
      if (customStart == null || customEnd == null) {
        return resolveTimeRange('last_3_months');
      }
      return (customStart, customEnd);
    case 'last_30_days':
      return (_iso(today.subtract(const Duration(days: 29))), _iso(today));
    case 'last_3_months':
      return (_iso(today.subtract(const Duration(days: 89))), _iso(today));
    case 'last_6_months':
      return (_iso(today.subtract(const Duration(days: 179))), _iso(today));
    case 'last_12_months':
      return (_iso(today.subtract(const Duration(days: 364))), _iso(today));
    case 'month_to_date':
      return (_iso(DateTime(today.year, today.month, 1)), _iso(today));
    case 'year_to_date':
      return (_iso(DateTime(today.year, 1, 1)), _iso(today));
    case 'all_time':
      return (_allTimeStart, _iso(today));
    default:
      return resolveTimeRange('last_3_months');
  }
}

(String, String) _previousWindow(String startIso, String endIso) {
  final s = _parse(startIso);
  final e = _parse(endIso);
  final length = e.difference(s).inDays + 1;
  final prevEnd = s.subtract(const Duration(days: 1));
  final prevStart = prevEnd.subtract(Duration(days: length - 1));
  return (_iso(prevStart), _iso(prevEnd));
}

(String, String) _priorYearWindow(String startIso, String endIso) {
  final s = _parse(startIso);
  final e = _parse(endIso);
  return (
    _iso(DateTime(s.year - 1, s.month, s.day)),
    _iso(DateTime(e.year - 1, e.month, e.day)),
  );
}

// ── Bucketing + labels (mirrors _bucket_expr / _label_for) ───────────────────

String _bucketStart(String dateIso, String bucket) {
  if (bucket == 'day') return dateIso;
  final d = _parse(dateIso);
  if (bucket == 'week') {
    // Monday as week start. Dart weekday: Mon=1..Sun=7 → days back 0..6.
    final back = d.weekday - 1;
    return _iso(d.subtract(Duration(days: back)));
  }
  if (bucket == 'month') return _iso(DateTime(d.year, d.month, 1));
  throw ArgumentError('unsupported bucket: $bucket');
}

String _labelFor(String periodStart, String bucket) {
  final d = _parse(periodStart);
  final mon = _monthsShort[d.month - 1];
  if (bucket == 'month') return '$mon ${d.year.toString().substring(2)}';
  if (bucket == 'week') return 'Wk of $mon ${d.day}';
  return '$mon ${d.day}';
}

// ── Category helpers ─────────────────────────────────────────────────────────

/// Ids of the category at [path] and all its descendants.
Set<int> _descendantIds(List<Map<String, dynamic>> cats, String path) {
  final prefix = '$path / ';
  return {
    for (final c in cats)
      if (c['path'] == path || (c['path'] as String).startsWith(prefix))
        c['id'] as int,
  };
}

/// Transactions matching an optional category-path filter, where the literal
/// "Unknown" means uncategorised (null category), mirroring the backend.
Iterable<Map<String, dynamic>> _filterByCategory(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  String? categoryPath,
) {
  if (categoryPath == null || categoryPath.isEmpty) return txns;
  if (categoryPath == 'Unknown') {
    return txns.where((t) => t['category_id'] == null);
  }
  final ids = _descendantIds(cats, categoryPath);
  if (ids.isEmpty) return const [];
  return txns.where((t) => ids.contains(t['category_id']));
}

bool _inWindow(Map<String, dynamic> t, String start, String end) {
  final d = t['date'] as String;
  return d.compareTo(start) >= 0 && d.compareTo(end) <= 0;
}

// ── Aggregations (mirrors mcp_server tools) ──────────────────────────────────

/// Returns rows `{period_start, period_label, value}` ordered by period.
List<Map<String, dynamic>> aggregateSpending(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  String start,
  String end,
  String bucket,
  String? categoryPath,
) {
  final totals = <String, double>{};
  for (final t in _filterByCategory(cats, txns, categoryPath)) {
    if (!_inWindow(t, start, end)) continue;
    final period = _bucketStart(t['date'] as String, bucket);
    totals[period] = (totals[period] ?? 0) + (t['amount'] as num).toDouble();
  }
  final periods = totals.keys.toList()..sort();
  return [
    for (final p in periods)
      {
        'period_start': p,
        'period_label': _labelFor(p, bucket),
        'value': _round2(totals[p]!),
      },
  ];
}

double totalForWindow(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  String start,
  String end,
  String? categoryPath,
) {
  double sum = 0;
  for (final t in _filterByCategory(cats, txns, categoryPath)) {
    if (_inWindow(t, start, end)) sum += (t['amount'] as num).toDouble();
  }
  return _round2(sum);
}

/// `{merchant, total}` rows ordered by total desc, limited.
List<Map<String, dynamic>> topMerchants(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  String start,
  String end,
  String? categoryPath,
  int limit,
) {
  final totals = <String, double>{};
  for (final t in _filterByCategory(cats, txns, categoryPath)) {
    if (!_inWindow(t, start, end)) continue;
    final m = t['merchant'] as String;
    totals[m] = (totals[m] ?? 0) + (t['amount'] as num).toDouble();
  }
  final entries = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in entries.take(limit))
      {'merchant': e.key, 'total': _round2(e.value)},
  ];
}

bool _isTopLevel(Set<int> idSet, Map<String, dynamic> c) =>
    !idSet.contains(c['parent_id']);

List<(String, double)> _topLevelTotals(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  String start,
  String end,
) {
  final idSet = {for (final c in cats) c['id'] as int};
  final items = <(String, double)>[];
  for (final top in cats) {
    if (!_isTopLevel(idSet, top)) continue;
    if (top['is_unknown'] == true) continue;
    final total = totalForWindow(cats, txns, start, end, top['path'] as String);
    if (total != 0) items.add((top['name'] as String, total));
  }
  final unassigned =
      totalForWindow(cats, txns, start, end, 'Unknown');
  if (unassigned != 0) items.add(('Unassigned', unassigned));
  return items;
}

List<(String, double)> _categoryChildrenTotals(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  String start,
  String end,
  String parentPath,
) {
  final parent = cats.where((c) => c['path'] == parentPath);
  if (parent.isEmpty) return const [];
  final parentId = parent.first['id'] as int;
  final items = <(String, double)>[];
  for (final c in cats) {
    if (c['parent_id'] != parentId || c['is_unknown'] == true) continue;
    final total = totalForWindow(cats, txns, start, end, c['path'] as String);
    if (total != 0) items.add((c['name'] as String, total));
  }
  return items;
}

/// `{historical, forecast}`, mirroring mcp_server.forecast.
Map<String, dynamic> _forecast(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  int horizon,
  String? categoryPath,
  String method,
) {
  final today = demoToday();
  final startMonth = DateTime(today.year, today.month, 1)
      .subtract(const Duration(days: 365));
  final historical = aggregateSpending(
      cats, txns, _iso(startMonth), _iso(today), 'month', categoryPath);
  final values = [for (final h in historical) (h['value'] as num).toDouble()];
  if (values.isEmpty) {
    return {'historical': historical, 'forecast': <Map<String, dynamic>>[]};
  }

  List<double> proj;
  if (method == 'linear' && values.length >= 2) {
    final n = values.length;
    final xs = [for (var i = 0; i < n; i++) i];
    final sx = xs.reduce((a, b) => a + b).toDouble();
    final sy = values.reduce((a, b) => a + b);
    var sxy = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += xs[i] * values[i];
    }
    final sxx = xs.fold<double>(0, (a, x) => a + x * x);
    final denom = n * sxx - sx * sx;
    final a = denom != 0 ? (n * sxy - sx * sy) / denom : 0.0;
    final b = (sy - a * sx) / n;
    proj = [for (var i = 0; i < horizon; i++) _round2(a * (n + i) + b)];
  } else {
    final recent = values.length >= 6 ? values.sublist(values.length - 6) : values;
    final avg = _round2(recent.reduce((a, b) => a + b) / recent.length);
    proj = List.filled(horizon, avg);
  }

  final lastPeriod = historical.last['period_start'] as String;
  final lastYear = int.parse(lastPeriod.substring(0, 4));
  final lastMonth = int.parse(lastPeriod.substring(5, 7));
  final forecastRows = <Map<String, dynamic>>[];
  for (var i = 1; i <= horizon; i++) {
    var m = lastMonth + i;
    final y = lastYear + (m - 1) ~/ 12;
    m = ((m - 1) % 12) + 1;
    final periodStart =
        '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-01';
    forecastRows.add({
      'period_start': periodStart,
      'period_label': _labelFor(periodStart, 'month'),
      'value': proj[i - 1],
    });
  }
  return {'historical': historical, 'forecast': forecastRows};
}

// ── Shape adapters (mirrors _wrap_* / _items_from_dispatch) ──────────────────

Map<String, dynamic> _wrapTimeseriesSingle(
  String title,
  List<(String, double)> points, {
  String? yLabel,
}) {
  return {
    'chart': {
      'title': title,
      'y_axis_label': yLabel,
      'x_axis_label': null,
      'x_tick_labels': [for (final p in points) p.$1],
      'series': [
        {
          'label': title,
          'style': 'solid',
          'points': [
            for (var i = 0; i < points.length; i++)
              {'x': i.toDouble(), 'y': points[i].$2},
          ],
        },
      ],
    },
  };
}

Map<String, dynamic> _wrapBar(List<(String, double)> items) =>
    {'categories': [for (final it in items) {'label': it.$1, 'value': it.$2}]};

Map<String, dynamic> _wrapPie(List<(String, double)> items) {
  final total = items.fold<double>(0, (a, it) => a + it.$2);
  return {
    'slices': [for (final it in items) {'label': it.$1, 'value': it.$2}],
    'total': _round2(total),
  };
}

Map<String, dynamic> _wrapTreemap(List<(String, double)> items) =>
    {'nodes': [for (final it in items) {'label': it.$1, 'value': it.$2}]};

Map<String, dynamic> _wrapTable(
        List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows) =>
    {'columns': columns, 'rows': rows};

Map<String, dynamic> _wrapQueryValue(
  double value, {
  String fmt = 'currency',
  Map<String, dynamic>? comparison,
  List<double>? sparkline,
  String? unit,
}) {
  return {
    'value': _round2(value),
    'format': fmt,
    'comparison': ?comparison,
    'sparkline': ?sparkline,
    'unit': ?unit,
  };
}

Map<String, dynamic> _itemsFromDispatch(
  List<(String, double)> items,
  String widgetType, {
  required String title,
  String valueFormat = 'currency',
  String tableLabel = 'Label',
  String tableValue = 'Value',
}) {
  switch (widgetType) {
    case 'bar':
      return _wrapBar(items);
    case 'pie':
      return _wrapPie(items);
    case 'treemap':
      return _wrapTreemap(items);
    case 'table':
      return _wrapTable(
        [
          {'key': 'label', 'label': tableLabel, 'align': 'left'},
          {'key': 'value', 'label': tableValue, 'align': 'right', 'format': valueFormat},
        ],
        [for (final it in items) {'label': it.$1, 'value': it.$2}],
      );
    case 'query_value':
      return _wrapQueryValue(items.fold<double>(0, (a, it) => a + it.$2),
          fmt: valueFormat);
    case 'timeseries':
      return _wrapTimeseriesSingle(title, items);
    default:
      throw _MetricError('widget type $widgetType is not supported by this metric');
  }
}

class _MetricError implements Exception {
  _MetricError(this.message);
  final String message;
}

// ── Public entry point (mirrors resolve_metric_data) ─────────────────────────

String? _param(Map<String, dynamic>? params, String name) {
  final v = params?[name];
  if (v == null || v == '') return null;
  return v.toString();
}

/// Resolve a metric to its widget `data` dict. [timeRange] is the dashboard's
/// resolved (start, end). Throws on an incompatible widget type.
Map<String, dynamic> resolveMetricData(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  String metricId,
  Map<String, dynamic> params,
  String widgetType,
  (String, String) timeRange,
) {
  final (start, end) = timeRange;
  switch (metricId) {
    case 'spend_over_time':
      {
        final bucket = _param(params, 'rollup_period') ?? 'day';
        final category = _param(params, 'category_path');
        final rows = aggregateSpending(cats, txns, start, end, bucket, category);
        final points = [
          for (final r in rows)
            (r['period_label'] as String, (r['value'] as num).toDouble())
        ];
        final title = 'Spend over time${category != null ? ' — $category' : ''}';
        if (widgetType == 'timeseries') {
          return _wrapTimeseriesSingle(title, points, yLabel: 'USD');
        }
        return _itemsFromDispatch(points, widgetType,
            title: title, tableLabel: 'Period', tableValue: 'Spend');
      }
    case 'spend_by_category':
      {
        final parent = _param(params, 'parent_category');
        List<(String, double)> items;
        String title;
        if (parent != null) {
          items = _categoryChildrenTotals(cats, txns, start, end, parent);
          title = 'Spend within $parent';
        } else {
          items = _topLevelTotals(cats, txns, start, end);
          title = 'Spend by category';
        }
        items.sort((a, b) => b.$2.compareTo(a.$2));
        return _itemsFromDispatch(items, widgetType,
            title: title, tableLabel: 'Category', tableValue: 'Spend');
      }
    case 'top_merchants':
      {
        final category = _param(params, 'category_path');
        final limit = int.tryParse(_param(params, 'limit') ?? '10') ?? 10;
        final rows = topMerchants(cats, txns, start, end, category, limit);
        final items = [
          for (final r in rows)
            (r['merchant'] as String, (r['total'] as num).toDouble())
        ];
        final title = 'Top merchants${category != null ? ' — $category' : ''}';
        return _itemsFromDispatch(items, widgetType,
            title: title, tableLabel: 'Merchant', tableValue: 'Spend');
      }
    case 'total_spend':
      {
        final category = _param(params, 'category_path');
        final compare = params['compare_to_previous'] == true;
        final rows = aggregateSpending(cats, txns, start, end, 'month', category);
        final total = _round2(
            rows.fold<double>(0, (a, r) => a + (r['value'] as num).toDouble()));
        if (widgetType == 'query_value') {
          Map<String, dynamic>? comparison;
          final sparkline = rows.isNotEmpty
              ? [for (final r in rows) (r['value'] as num).toDouble()]
              : null;
          if (compare) {
            final (ps, pe) = _previousWindow(start, end);
            final prevRows = aggregateSpending(cats, txns, ps, pe, 'month', category);
            final prevTotal = _round2(prevRows.fold<double>(
                0, (a, r) => a + (r['value'] as num).toDouble()));
            comparison = {
              'value': prevTotal,
              'delta_abs': _round2(total - prevTotal),
              'delta_pct': prevTotal != 0
                  ? _round2((total - prevTotal) / prevTotal * 100)
                  : null,
              'label': 'vs. previous',
            };
          }
          return _wrapQueryValue(total, comparison: comparison, sparkline: sparkline);
        }
        return _itemsFromDispatch([('$start → $end', total)], widgetType,
            title: 'Total spend', tableLabel: 'Window', tableValue: 'Total');
      }
    case 'average_per_period':
      {
        final bucket = _param(params, 'rollup_period') ?? 'month';
        final category = _param(params, 'category_path');
        final rows = aggregateSpending(cats, txns, start, end, bucket, category);
        final values = [for (final r in rows) (r['value'] as num).toDouble()];
        final avg = values.isNotEmpty
            ? _round2(values.reduce((a, b) => a + b) / values.length)
            : 0.0;
        if (widgetType == 'query_value') {
          return _wrapQueryValue(avg,
              sparkline: values.isNotEmpty ? values : null, unit: bucket);
        }
        return _itemsFromDispatch([('avg / $bucket', avg)], widgetType,
            title: 'Average per $bucket', tableLabel: 'Metric', tableValue: 'Average');
      }
    case 'transaction_count':
      {
        final category = _param(params, 'category_path');
        final count = _filterByCategory(cats, txns, category)
            .where((t) => _inWindow(t, start, end))
            .length;
        if (widgetType == 'query_value') {
          return _wrapQueryValue(count.toDouble(), fmt: 'number');
        }
        return _itemsFromDispatch([('$start → $end', count.toDouble())], widgetType,
            title: 'Transactions',
            valueFormat: 'number',
            tableLabel: 'Window',
            tableValue: 'Count');
      }
    case 'period_comparison':
      {
        final baselineKind = _param(params, 'baseline_kind') ?? 'previous_period';
        final category = _param(params, 'category_path');
        final (bs, be) = baselineKind == 'prior_year'
            ? _priorYearWindow(start, end)
            : _previousWindow(start, end);
        final aTotal = totalForWindow(cats, txns, bs, be, category);
        final bTotal = totalForWindow(cats, txns, start, end, category);
        final label =
            baselineKind == 'previous_period' ? 'vs. previous period' : 'vs. prior year';
        if (widgetType == 'query_value') {
          return _wrapQueryValue(bTotal, comparison: {
            'value': aTotal,
            'delta_abs': _round2(bTotal - aTotal),
            'delta_pct': aTotal != 0 ? _round2((bTotal - aTotal) / aTotal * 100) : null,
            'label': label,
          });
        }
        return _itemsFromDispatch([
          ('baseline ($bs → $be)', aTotal),
          ('current ($start → $end)', bTotal),
        ], widgetType, title: 'Period comparison', tableLabel: 'Window', tableValue: 'Total');
      }
    case 'spend_forecast':
      {
        final horizon = int.tryParse(_param(params, 'horizon_months') ?? '3') ?? 3;
        final category = _param(params, 'category_path');
        final method = _param(params, 'method') ?? 'trailing_avg';
        final result = _forecast(cats, txns, horizon, category, method);
        final historical = (result['historical'] as List).cast<Map<String, dynamic>>();
        final forecast = (result['forecast'] as List).cast<Map<String, dynamic>>();
        final xTicks = [
          for (final r in historical) r['period_label'],
          for (final r in forecast) r['period_label'],
        ];
        final nH = historical.length;
        final hPoints = [
          for (var i = 0; i < historical.length; i++)
            {'x': i.toDouble(), 'y': (historical[i]['value'] as num).toDouble()},
        ];
        final fPoints = <Map<String, dynamic>>[];
        if (nH > 0) {
          fPoints.add({
            'x': (nH - 1).toDouble(),
            'y': (historical.last['value'] as num).toDouble(),
          });
        }
        for (var i = 0; i < forecast.length; i++) {
          fPoints.add({'x': (nH + i).toDouble(), 'y': (forecast[i]['value'] as num).toDouble()});
        }
        final chart = {
          'title': 'Spend forecast${category != null ? ' — $category' : ''}',
          'y_axis_label': 'USD',
          'x_axis_label': null,
          'x_tick_labels': xTicks.isNotEmpty ? xTicks : null,
          'series': [
            {'label': 'Historical', 'style': 'solid', 'points': hPoints},
            {'label': 'Forecast', 'style': 'dashed', 'points': fPoints},
          ],
        };
        if (widgetType == 'timeseries') return {'chart': chart};
        final items = [
          for (final r in forecast)
            (r['period_label'] as String, (r['value'] as num).toDouble())
        ];
        return _itemsFromDispatch(items, widgetType,
            title: 'Forecast', tableLabel: 'Period', tableValue: 'Forecast');
      }
    case 'recent_transactions':
      {
        final category = _param(params, 'category_path');
        final limit = int.tryParse(_param(params, 'limit') ?? '20') ?? 20;
        final rows = _filterByCategory(cats, txns, category)
            .where((t) => _inWindow(t, start, end))
            .toList()
          ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
        final top = rows.take(limit).toList();
        if (widgetType == 'table') {
          return _wrapTable(
            [
              {'key': 'date', 'label': 'Date', 'align': 'left'},
              {'key': 'merchant', 'label': 'Merchant', 'align': 'left'},
              {'key': 'category', 'label': 'Category', 'align': 'left'},
              {'key': 'amount', 'label': 'Amount', 'align': 'right', 'format': 'currency'},
            ],
            [
              for (final r in top)
                {
                  'date': r['date'],
                  'merchant': r['merchant'],
                  'category': r['category_path'] ?? '—',
                  'amount': (r['amount'] as num).toDouble(),
                },
            ],
          );
        }
        final items = [
          for (final r in top)
            (r['merchant'] as String, (r['amount'] as num).toDouble())
        ];
        return _itemsFromDispatch(items, widgetType,
            title: 'Recent transactions', tableLabel: 'Merchant', tableValue: 'Amount');
      }
    default:
      throw _MetricError('unknown metric: $metricId');
  }
}
