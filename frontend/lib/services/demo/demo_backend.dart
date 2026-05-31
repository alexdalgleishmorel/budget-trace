/// In-memory stand-in for the FastAPI backend, used only by the static demo
/// build. Loads the bundled seed dataset once, then serves and mutates it
/// entirely in memory (state resets on page reload). Every method returns
/// JSON-ready maps/lists in the exact snake_case shape the real REST API
/// emits, or throws [DemoApiException] mapped to the real error envelope.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'demo_chat.dart';
import 'demo_metrics.dart';

/// Mirrors the backend's `{"detail": {"code", "message"}}` error envelope.
class DemoApiException implements Exception {
  DemoApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
}

const String _ts = '2026-04-30T12:00:00';

class DemoBackend {
  DemoBackend._();
  static final DemoBackend instance = DemoBackend._();

  bool _loaded = false;

  /// CategoryOut-shaped maps: {id, name, description, parent_id, path,
  /// is_leaf, is_unknown, color}.
  final List<Map<String, dynamic>> _categories = [];

  /// Stored transaction rows: {id, date, merchant, amount, category_id}.
  final List<Map<String, dynamic>> _txns = [];

  /// Dashboards, each {id, name, time_range, created_at, updated_at, widgets}.
  final List<Map<String, dynamic>> _dashboards = [];

  /// Chat sessions, each {id, title, created_at, updated_at, spent_usd,
  /// messages: [...]}.
  final List<Map<String, dynamic>> _sessions = [];

  /// Static widget-metrics registry, lifted from the seed asset.
  Map<String, dynamic> _widgetMetrics = const {};

  int _categoryId = 0;
  int _dashboardId = 0;
  int _widgetId = 0;
  int _sessionId = 0;
  int _messageId = 0;
  int _rootId = 1;

  late Map<String, dynamic> _me;

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/demo/seed.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;

    for (final c in (data['categories'] as List)) {
      _categories.add(Map<String, dynamic>.from(c as Map));
    }
    for (final t in (data['transactions'] as List)) {
      final m = Map<String, dynamic>.from(t as Map);
      _txns.add({
        'id': m['id'],
        'date': m['date'],
        'merchant': m['merchant'],
        'amount': (m['amount'] as num).toDouble(),
        'category_id': m['category_id'],
      });
    }
    _widgetMetrics = Map<String, dynamic>.from(data['widget_metrics'] as Map);

    _categoryId = _categories.fold<int>(0, (a, c) => (c['id'] as int) > a ? c['id'] as int : a);
    final ids = {for (final c in _categories) c['id'] as int};
    final parents = {for (final c in _categories) c['parent_id'] as int?};
    _rootId = parents.firstWhere((p) => p != null && !ids.contains(p), orElse: () => 1) ?? 1;

    _seedDashboards();
    _initMe();
    _loaded = true;
  }

  /// Seed a few populated, distinctly-named example dashboards so the Widgets
  /// tab isn't empty on first load and showcases every widget type / metric.
  void _seedDashboards() {
    Map<String, dynamic> w(int dashId, String type, String metricId,
        Map<String, dynamic> params, List<int> xywh) {
      return {
        'id': ++_widgetId,
        'dashboard_id': dashId,
        'type': type,
        'title': _deriveTitleStatic(type, metricId),
        'layout': {'x': xywh[0], 'y': xywh[1], 'w': xywh[2], 'h': xywh[3]},
        'data_source': {'kind': 'metric', 'metric_id': metricId, 'params': params},
        'config': const {},
        'created_at': _ts,
        'updated_at': _ts,
      };
    }

    void dash(int id, String name, String preset, List<Map<String, dynamic>> widgets) {
      _dashboards.add({
        'id': id,
        'name': name,
        'time_range': {'preset': preset},
        'created_at': _ts,
        'updated_at': _ts,
        'widgets': widgets,
      });
    }

    dash(1, 'Monthly Overview', 'last_12_months', [
      w(1, 'query_value', 'total_spend', {'compare_to_previous': true}, [0, 0, 2, 2]),
      w(1, 'query_value', 'transaction_count', {}, [2, 0, 2, 2]),
      w(1, 'pie', 'spend_by_category', {}, [4, 0, 2, 2]),
      w(1, 'timeseries', 'spend_over_time', {'rollup_period': 'month'}, [0, 2, 3, 2]),
      w(1, 'table', 'recent_transactions', {'limit': 8}, [3, 2, 3, 2]),
    ]);
    dash(2, 'Category Breakdown', 'last_6_months', [
      w(2, 'treemap', 'spend_by_category', {}, [0, 0, 3, 2]),
      w(2, 'bar', 'spend_by_category', {}, [3, 0, 3, 2]),
      w(2, 'table', 'spend_by_category', {}, [0, 2, 3, 2]),
      w(2, 'query_value', 'average_per_period', {'rollup_period': 'month'}, [3, 2, 2, 2]),
    ]);
    dash(3, 'Merchants & Forecast', 'last_12_months', [
      w(3, 'pie', 'top_merchants', {'limit': 8}, [0, 0, 3, 2]),
      w(3, 'bar', 'top_merchants', {'limit': 10}, [3, 0, 3, 2]),
      w(3, 'timeseries', 'spend_forecast', {'horizon_months': 3, 'method': 'trailing_avg'}, [0, 2, 3, 2]),
      w(3, 'query_value', 'total_spend', {'compare_to_previous': true}, [3, 2, 2, 2]),
    ]);
    _dashboardId = 3;
  }

  String _deriveTitleStatic(String type, String metricId) {
    final cap = '${type[0].toUpperCase()}${type.substring(1)}';
    return '$cap : ${_metricLabel(metricId)}';
  }

  void _initMe() {
    _me = {
      'features': {'ai': true, 'widgets': true},
      'theme': 'dark',
      'providers': [
        {'id': 'anthropic', 'display_name': 'Anthropic', 'env_var': 'ANTHROPIC_API_KEY', 'api_key_set': true, 'env_fallback': false},
        {'id': 'openai', 'display_name': 'OpenAI', 'env_var': 'OPENAI_API_KEY', 'api_key_set': false, 'env_fallback': false},
        {'id': 'google', 'display_name': 'Google Gemini', 'env_var': 'GEMINI_API_KEY', 'api_key_set': false, 'env_fallback': false},
      ],
      'selected_provider': 'anthropic',
      'selected_provider_key_available': true,
      'selected_model': 'claude-demo',
      'available_models': [
        {'id': 'claude-demo', 'provider': 'anthropic', 'display_name': 'Claude (demo)', 'input_per_mtok': 0.0, 'output_per_mtok': 0.0, 'pricing_available': true},
      ],
      'ai_spent_usd': 0.0,
      'last_dashboard_id': _dashboards.isNotEmpty ? _dashboards.first['id'] : null,
    };
  }

  // ── Category helpers ─────────────────────────────────────────────────────────

  Map<int, Map<String, dynamic>> get _byId =>
      {for (final c in _categories) c['id'] as int: c};

  String _pathFor(int id) {
    final byId = _byId;
    final names = <String>[];
    int? cur = id;
    while (cur != null && byId.containsKey(cur)) {
      final c = byId[cur]!;
      names.add(c['name'] as String);
      cur = c['parent_id'] as int?;
    }
    return names.reversed.join(' / ');
  }

  /// Recompute `path` + `is_leaf` for every category after a structural change.
  void _recompute() {
    final parentIds = {for (final c in _categories) c['parent_id'] as int?};
    for (final c in _categories) {
      c['path'] = _pathFor(c['id'] as int);
      c['is_leaf'] = !parentIds.contains(c['id']);
    }
  }

  Map<int, String> get _pathById =>
      {for (final c in _categories) c['id'] as int: c['path'] as String};

  Map<String, dynamic> _catById(int id) {
    final c = _categories.where((c) => c['id'] == id);
    if (c.isEmpty) {
      throw DemoApiException(404, 'not_found', 'category not found');
    }
    return c.first;
  }

  /// Transactions enriched with `category_path` for output + metrics.
  List<Map<String, dynamic>> get _enrichedTxns {
    final paths = _pathById;
    return [
      for (final t in _txns)
        {...t, 'category_path': t['category_id'] != null ? paths[t['category_id']] : null},
    ];
  }

  // ── /me ──────────────────────────────────────────────────────────────────────

  Map<String, dynamic> me() => _me;

  Map<String, dynamic> patchMe(Map<String, dynamic> body) {
    if (body['features'] is Map) {
      _me['features'] = {...(_me['features'] as Map), ...(body['features'] as Map)};
    }
    if (body['theme'] is String) _me['theme'] = body['theme'];
    if (body['selected_provider'] is String) {
      _me['selected_provider'] = body['selected_provider'];
    }
    if (body.containsKey('selected_model')) {
      _me['selected_model'] = body['selected_model'] ?? '';
    }
    if (body['provider_keys'] is Map) {
      final keys = body['provider_keys'] as Map;
      for (final p in (_me['providers'] as List).cast<Map<String, dynamic>>()) {
        if (keys.containsKey(p['id'])) {
          p['api_key_set'] = keys[p['id']] != null;
        }
      }
      final sel = _me['selected_provider'];
      final selProvider = (_me['providers'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((p) => p['id'] == sel, orElse: () => {'api_key_set': true});
      _me['selected_provider_key_available'] = selProvider['api_key_set'] == true;
    }
    return _me;
  }

  Map<String, dynamic> refreshModels() => {
        'provider': {
          'provider': _me['selected_provider'],
          'ok': true,
          'discovered_count': 0,
          'skipped': false,
          'error': null,
        },
        'available_models': _me['available_models'],
      };

  // ── Categories ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> listCategories() => _categories;

  Map<String, dynamic> createCategory(Map<String, dynamic> body) {
    final parentId = body['parent_id'] as int? ?? _rootId;
    final cat = {
      'id': ++_categoryId,
      'name': body['name'] as String,
      'description': body['description'] as String?,
      'parent_id': parentId,
      'path': '',
      'is_leaf': true,
      'is_unknown': false,
      'color': body['color'] as String? ?? 'sky',
    };
    _categories.add(cat);
    _recompute();
    return cat;
  }

  Map<String, dynamic> updateCategory(int id, Map<String, dynamic> body) {
    final cat = _catById(id);
    if (body.containsKey('name') && body['name'] != null) cat['name'] = body['name'];
    if (body.containsKey('description')) cat['description'] = body['description'];
    if (body.containsKey('parent_id')) cat['parent_id'] = body['parent_id'] ?? _rootId;
    if (body.containsKey('color') && body['color'] != null) cat['color'] = body['color'];
    _recompute();
    return cat;
  }

  Map<String, dynamic> deleteCategory(int id) {
    _catById(id); // 404 if missing
    final toRemove = <int>{id};
    bool grew = true;
    while (grew) {
      grew = false;
      for (final c in _categories) {
        if (toRemove.contains(c['parent_id']) && !toRemove.contains(c['id'])) {
          toRemove.add(c['id'] as int);
          grew = true;
        }
      }
    }
    var unassigned = 0;
    for (final t in _txns) {
      if (toRemove.contains(t['category_id'])) {
        t['category_id'] = null;
        unassigned++;
      }
    }
    _categories.removeWhere((c) => toRemove.contains(c['id']));
    _recompute();
    return {
      'deleted_id': id,
      'descendants_deleted': toRemove.length - 1,
      'transactions_unassigned': unassigned,
    };
  }

  List<Map<String, dynamic>> seedDefaults() {
    throw DemoApiException(409, 'categories_exist',
        'Default categories can only be added when the tree is empty.');
  }

  // ── Transactions ─────────────────────────────────────────────────────────────

  Map<String, dynamic> latestDate() {
    if (_txns.isEmpty) return {'date': null};
    final max = _txns.map((t) => t['date'] as String).reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    return {'date': max};
  }

  List<Map<String, dynamic>> listTransactions(Map<String, String> q) {
    final start = q['start_date'];
    final end = q['end_date'];
    final categoryId = q['category_id'] != null ? int.tryParse(q['category_id']!) : null;
    final categoryPath = q['category_path'];
    final uncategorised = q['uncategorised'] == 'true';
    final merchantQuery = q['merchant_query']?.toLowerCase();
    final limit = int.tryParse(q['limit'] ?? '100') ?? 100;

    Set<int>? pathIds;
    if (!uncategorised && categoryId == null && categoryPath != null && categoryPath != 'Unknown') {
      pathIds = {
        for (final c in _categories)
          if (c['path'] == categoryPath || (c['path'] as String).startsWith('$categoryPath / '))
            c['id'] as int,
      };
    }

    final paths = _pathById;
    final rows = <Map<String, dynamic>>[];
    for (final t in _txns) {
      final d = t['date'] as String;
      if (start != null && d.compareTo(start) < 0) continue;
      if (end != null && d.compareTo(end) > 0) continue;
      final cid = t['category_id'] as int?;
      if (uncategorised) {
        if (cid != null) continue;
      } else if (categoryId != null) {
        if (cid != categoryId) continue;
      } else if (categoryPath == 'Unknown') {
        if (cid != null) continue;
      } else if (pathIds != null) {
        if (cid == null || !pathIds.contains(cid)) continue;
      }
      if (merchantQuery != null && merchantQuery.isNotEmpty &&
          !(t['merchant'] as String).toLowerCase().contains(merchantQuery)) {
        continue;
      }
      rows.add({
        'id': t['id'],
        'date': d,
        'merchant': t['merchant'],
        'amount': t['amount'],
        'category_id': cid,
        'category_path': cid != null ? paths[cid] : null,
      });
    }
    rows.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return rows.take(limit).toList();
  }

  Map<String, dynamic> _txnOut(Map<String, dynamic> t) {
    final cid = t['category_id'] as int?;
    return {
      'id': t['id'],
      'date': t['date'],
      'merchant': t['merchant'],
      'amount': t['amount'],
      'category_id': cid,
      'category_path': cid != null ? _pathById[cid] : null,
    };
  }

  Map<String, dynamic> _findTxn(int id) {
    final t = _txns.where((t) => t['id'] == id);
    if (t.isEmpty) throw DemoApiException(404, 'not_found', 'transaction not found');
    return t.first;
  }

  Map<String, dynamic> updateTransaction(int id, Map<String, dynamic> body) {
    final t = _findTxn(id);
    if (body['date'] != null) t['date'] = body['date'];
    if (body['merchant'] != null) t['merchant'] = body['merchant'];
    if (body['amount'] != null) t['amount'] = (body['amount'] as num).toDouble();
    if (body.containsKey('category_id')) t['category_id'] = body['category_id'];
    return _txnOut(t);
  }

  void deleteTransaction(int id) {
    _findTxn(id);
    _txns.removeWhere((t) => t['id'] == id);
  }

  Map<String, dynamic> bulkRename(Map<String, dynamic> body) {
    final from = body['from_merchant'] as String;
    final to = body['to_merchant'] as String;
    var n = 0;
    for (final t in _txns) {
      if (t['merchant'] == from) {
        t['merchant'] = to;
        n++;
      }
    }
    return {'updated': n};
  }

  /// Mocked import. The demo never mutates its dataset on upload — it just
  /// counts the rows in the file and reports them all as successfully added.
  /// The UI shows a clear "no real data was uploaded" note (kDemoMode). This
  /// keeps the upload flow demoable while staying honest about being a mock.
  Map<String, dynamic> importCsv(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final lines =
        const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return _importResult(0);
    // Treat a first row that looks like a header as non-data.
    final first = lines.first.toLowerCase();
    final hasHeader = first.contains('date') || first.contains('amount') ||
        first.contains('merchant') || first.contains('description');
    final rows = hasHeader ? lines.length - 1 : lines.length;
    return _importResult(rows < 0 ? 0 : rows);
  }

  Map<String, dynamic> _importResult(int rows) => {
        'format_detected': 'csv',
        // All-success mock: parsed == inserted, nothing failed or duplicated.
        'rows_parsed': rows,
        'rows_inserted': rows,
        'rows_skipped_duplicate': 0,
        'rows_failed': 0,
        'errors': const [],
        'categorization': null,
      };

  // ── Dashboards + widgets ─────────────────────────────────────────────────────

  Map<String, dynamic> _dashSummary(Map<String, dynamic> d) => {
        'id': d['id'],
        'name': d['name'],
        'time_range': d['time_range'],
        'created_at': d['created_at'],
        'updated_at': d['updated_at'],
      };

  List<Map<String, dynamic>> listDashboards() =>
      [for (final d in _dashboards) _dashSummary(d)];

  Map<String, dynamic> _findDash(int id) {
    final d = _dashboards.where((d) => d['id'] == id);
    if (d.isEmpty) throw DemoApiException(404, 'not_found', 'dashboard not found');
    return d.first;
  }

  Map<String, dynamic> createDashboard(Map<String, dynamic> body) {
    final d = {
      'id': ++_dashboardId,
      'name': body['name'] as String? ?? 'Untitled',
      'time_range': {'preset': 'last_3_months'},
      'created_at': _ts,
      'updated_at': _ts,
      'widgets': <Map<String, dynamic>>[],
    };
    _dashboards.add(d);
    return _dashSummary(d);
  }

  Map<String, dynamic> getDashboard(int id) {
    final d = _findDash(id);
    return {
      ..._dashSummary(d),
      'widgets': d['widgets'],
    };
  }

  Map<String, dynamic> updateDashboard(int id, Map<String, dynamic> body) {
    final d = _findDash(id);
    if (body['name'] != null) d['name'] = body['name'];
    if (body['time_range'] is Map) d['time_range'] = Map<String, dynamic>.from(body['time_range'] as Map);
    return _dashSummary(d);
  }

  void deleteDashboard(int id) {
    _findDash(id);
    _dashboards.removeWhere((d) => d['id'] == id);
    if (_me['last_dashboard_id'] == id) {
      _me['last_dashboard_id'] = _dashboards.isNotEmpty ? _dashboards.first['id'] : null;
    }
  }

  List<int> _minSize(String type) {
    final sizes = _widgetMetrics['widget_min_sizes'] as Map?;
    final s = sizes?[type];
    if (s is List && s.length >= 2) return [s[0] as int, s[1] as int];
    return [2, 2];
  }

  String _metricLabel(String? metricId) {
    if (metricId == null) return '';
    final metrics = (_widgetMetrics['metrics'] as List).cast<Map<String, dynamic>>();
    final m = metrics.where((m) => m['id'] == metricId);
    return m.isEmpty ? metricId : m.first['label'] as String;
  }

  String _deriveTitle(String type, Map<String, dynamic> dataSource) {
    final cap = type.isEmpty ? type : '${type[0].toUpperCase()}${type.substring(1)}';
    if (dataSource['kind'] == 'metric') {
      return '$cap : ${_metricLabel(dataSource['metric_id'] as String?)}';
    }
    return cap;
  }

  Map<String, dynamic> createWidget(int dashboardId, Map<String, dynamic> body) {
    final d = _findDash(dashboardId);
    final widgets = (d['widgets'] as List).cast<Map<String, dynamic>>();
    final type = body['type'] as String;
    final dataSource = Map<String, dynamic>.from(body['data_source'] as Map);
    final min = _minSize(type);
    Map<String, dynamic> layout;
    if (body['layout'] is Map) {
      layout = Map<String, dynamic>.from(body['layout'] as Map);
    } else {
      final maxY = widgets.fold<int>(0, (a, w) {
        final l = w['layout'] as Map;
        final bottom = (l['y'] as int) + (l['h'] as int);
        return bottom > a ? bottom : a;
      });
      layout = {'x': 0, 'y': maxY, 'w': min[0], 'h': min[1]};
    }
    final widget = {
      'id': ++_widgetId,
      'dashboard_id': dashboardId,
      'type': type,
      'title': (body['title'] as String?)?.isNotEmpty == true
          ? body['title']
          : _deriveTitle(type, dataSource),
      'layout': layout,
      'data_source': dataSource,
      'config': Map<String, dynamic>.from((body['config'] as Map?) ?? const {}),
      'created_at': _ts,
      'updated_at': _ts,
    };
    widgets.add(widget);
    return widget;
  }

  Map<String, dynamic> _findWidget(int dashboardId, int widgetId) {
    final d = _findDash(dashboardId);
    final w = (d['widgets'] as List).cast<Map<String, dynamic>>().where((w) => w['id'] == widgetId);
    if (w.isEmpty) throw DemoApiException(404, 'not_found', 'widget not found');
    return w.first;
  }

  Map<String, dynamic> updateWidget(int dashboardId, int widgetId, Map<String, dynamic> body) {
    final w = _findWidget(dashboardId, widgetId);
    if (body['data_source'] is Map) {
      w['data_source'] = Map<String, dynamic>.from(body['data_source'] as Map);
    }
    if (body.containsKey('title')) {
      final t = body['title'] as String?;
      w['title'] = (t != null && t.isNotEmpty)
          ? t
          : _deriveTitle(w['type'] as String, w['data_source'] as Map<String, dynamic>);
    }
    if (body['layout'] is Map) w['layout'] = Map<String, dynamic>.from(body['layout'] as Map);
    if (body['config'] is Map) w['config'] = Map<String, dynamic>.from(body['config'] as Map);
    return w;
  }

  void deleteWidget(int dashboardId, int widgetId) {
    final d = _findDash(dashboardId);
    (d['widgets'] as List).removeWhere((w) => w['id'] == widgetId);
  }

  void putLayout(int dashboardId, Map<String, dynamic> body) {
    final d = _findDash(dashboardId);
    final widgets = (d['widgets'] as List).cast<Map<String, dynamic>>();
    for (final entry in (body['layouts'] as List).cast<Map<String, dynamic>>()) {
      final w = widgets.where((w) => w['id'] == entry['id']);
      if (w.isNotEmpty) {
        w.first['layout'] = {'x': entry['x'], 'y': entry['y'], 'w': entry['w'], 'h': entry['h']};
      }
    }
  }

  Map<String, dynamic> getWidgetData(int dashboardId, int widgetId) {
    final d = _findDash(dashboardId);
    final w = _findWidget(dashboardId, widgetId);
    final type = w['type'] as String;
    final dataSource = w['data_source'] as Map<String, dynamic>;
    if (dataSource['kind'] == 'snapshot') {
      return {
        'type': type,
        'data': w['_snapshot_data'] ?? const {},
        'is_snapshot': true,
        'via_chat': w['_via_chat'] == true,
      };
    }
    final tr = d['time_range'] as Map<String, dynamic>;
    final metric = (_widgetMetrics['metrics'] as List).cast<Map<String, dynamic>>();
    final mid = dataSource['metric_id'] as String;
    final usesTimeRange = metric
            .firstWhere((m) => m['id'] == mid, orElse: () => const {'uses_time_range': true})['uses_time_range'] !=
        false;
    final range = usesTimeRange
        ? resolveTimeRange(tr['preset'] as String?, tr['custom_start'] as String?, tr['custom_end'] as String?)
        : resolveTimeRange('last_12_months');
    final data = resolveMetricData(
      _categories,
      _enrichedTxns,
      mid,
      Map<String, dynamic>.from((dataSource['params'] as Map?) ?? const {}),
      type,
      range,
    );
    return {'type': type, 'data': data, 'is_snapshot': false, 'via_chat': false};
  }

  Map<String, dynamic> widgetMetrics() => _widgetMetrics;

  // ── Chat ──────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> listSessions() => [
        for (final s in _sessions.reversed)
          {
            'id': s['id'],
            'title': s['title'],
            'created_at': s['created_at'],
            'updated_at': s['updated_at'],
            'message_count': (s['messages'] as List).length,
            'spent_usd': s['spent_usd'],
          },
      ];

  Map<String, dynamic> _findSession(int id) {
    final s = _sessions.where((s) => s['id'] == id);
    if (s.isEmpty) throw DemoApiException(404, 'not_found', 'session not found');
    return s.first;
  }

  Map<String, dynamic> createSession() {
    final s = {
      'id': ++_sessionId,
      'title': 'New chat',
      'created_at': _ts,
      'updated_at': _ts,
      'spent_usd': 0.0,
      'messages': <Map<String, dynamic>>[],
    };
    _sessions.add(s);
    return {
      'id': s['id'],
      'title': s['title'],
      'created_at': s['created_at'],
      'updated_at': s['updated_at'],
      'message_count': 0,
      'spent_usd': 0.0,
    };
  }

  List<Map<String, dynamic>> getMessages(int sessionId) =>
      (_findSession(sessionId)['messages'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> appendMessage(int sessionId, String text) {
    final s = _findSession(sessionId);
    final messages = s['messages'] as List;
    final userMsg = {
      'id': ++_messageId,
      'role': 'user',
      'text': text,
      'widget': null,
      'errored': false,
    };
    messages.add(userMsg);
    if ((s['title'] as String) == 'New chat' && text.trim().isNotEmpty) {
      s['title'] = text.trim().length > 48 ? '${text.trim().substring(0, 48)}…' : text.trim();
    }

    final reply = buildScriptedReply(text, _categories, _enrichedTxns);
    final assistantMsg = {
      'id': ++_messageId,
      'role': 'assistant',
      'text': reply.text,
      'widget': reply.widget,
      'errored': false,
    };
    messages.add(assistantMsg);
    return {
      'user_message': userMsg,
      'assistant_message': assistantMsg,
      'cost_usd': 0.0,
      'session_spent_usd': s['spent_usd'],
    };
  }

  void deleteSession(int sessionId) {
    _findSession(sessionId);
    _sessions.removeWhere((s) => s['id'] == sessionId);
  }

  Map<String, dynamic> chatHelp() => {'text': demoChatHelpText};

  Map<String, dynamic> saveChatWidget(int messageId, int dashboardId) {
    Map<String, dynamic>? widget;
    for (final s in _sessions) {
      for (final m in (s['messages'] as List).cast<Map<String, dynamic>>()) {
        if (m['id'] == messageId && m['widget'] is Map) {
          widget = m['widget'] as Map<String, dynamic>;
        }
      }
    }
    if (widget == null) {
      throw DemoApiException(404, 'not_found', 'message has no widget');
    }
    final type = widget['type'] as String;
    final metricId = widget['metric_id'] as String?;
    Map<String, dynamic> dataSource;
    if (metricId != null) {
      dataSource = {
        'kind': 'metric',
        'metric_id': metricId,
        'params': Map<String, dynamic>.from((widget['metric_params'] as Map?) ?? const {}),
      };
    } else {
      dataSource = {'kind': 'snapshot'};
    }
    final created = createWidget(dashboardId, {
      'type': type,
      'title': widget['title'],
      'data_source': dataSource,
      'config': const {},
    });
    if (metricId == null) {
      created['_snapshot_data'] = widget['data'];
      created['_via_chat'] = true;
    }
    return created;
  }
}
