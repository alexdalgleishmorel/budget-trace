import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dashboard.dart';
import 'api_base.dart';

/// REST client for the Widgets feature. Mirrors the snake_case API surface
/// in `routes/dashboards.py` — see [docs/rest-api.md] when adding methods.
class DashboardsClient {
  DashboardsClient({http.Client? client}) : _client = client ?? makeHttpClient();

  final http.Client _client;
  static const _jsonHeaders = {'Content-Type': 'application/json'};

  // ── Dashboards ─────────────────────────────────────────────────────────────

  Future<List<DashboardSummary>> list() async {
    final resp = await _client.get(Uri.parse('$apiBaseUrl/dashboards'));
    final body = decodeOrThrow(resp) as List;
    return body
        .map((j) => DashboardSummary.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<DashboardSummary> create({required String name}) async {
    final resp = await _client.post(
      Uri.parse('$apiBaseUrl/dashboards'),
      headers: _jsonHeaders,
      body: jsonEncode({'name': name}),
    );
    return DashboardSummary.fromJson(
        decodeOrThrow(resp) as Map<String, dynamic>);
  }

  Future<Dashboard> get(int id) async {
    final resp = await _client.get(Uri.parse('$apiBaseUrl/dashboards/$id'));
    return Dashboard.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  /// Partial update. Pass at least one of `name` / `timeRange`. Either one
  /// alone is fine — the backend rejects the no-op call.
  Future<DashboardSummary> update(
    int id, {
    String? name,
    DashboardTimeRange? timeRange,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (timeRange != null) body['time_range'] = timeRange.toJson();
    final resp = await _client.patch(
      Uri.parse('$apiBaseUrl/dashboards/$id'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    return DashboardSummary.fromJson(
        decodeOrThrow(resp) as Map<String, dynamic>);
  }

  // Kept for any in-flight callers; new code should use `update(...)`.
  Future<DashboardSummary> rename(int id, String name) =>
      update(id, name: name);

  Future<void> delete(int id) async {
    final resp = await _client.delete(Uri.parse('$apiBaseUrl/dashboards/$id'));
    decodeOrThrow(resp);
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Future<DashboardWidget> createWidget(
    int dashboardId, {
    required String type,
    required WidgetDataSource dataSource,
    WidgetLayout? layout,
    Map<String, dynamic> config = const {},
  }) async {
    final body = <String, dynamic>{
      'type': type,
      'data_source': dataSource.toJson(),
      'config': config,
    };
    // Omit layout to let the server place the widget below the
    // existing grid at the type's min size.
    if (layout != null) body['layout'] = layout.toJson();
    final resp = await _client.post(
      Uri.parse('$apiBaseUrl/dashboards/$dashboardId/widgets'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    return DashboardWidget.fromJson(
        decodeOrThrow(resp) as Map<String, dynamic>);
  }

  Future<DashboardWidget> updateWidget(
    int dashboardId,
    int widgetId, {
    String? title,
    WidgetLayout? layout,
    WidgetDataSource? dataSource,
    Map<String, dynamic>? config,
  }) async {
    final body = <String, dynamic>{};
    // Empty string is meaningful — it tells the backend to reset to the
    // auto-derived `{Type} : {Metric}` title — so pass it through even
    // when empty as long as the caller explicitly provided it.
    if (title != null) body['title'] = title;
    if (layout != null) body['layout'] = layout.toJson();
    if (dataSource != null) body['data_source'] = dataSource.toJson();
    if (config != null) body['config'] = config;
    final resp = await _client.patch(
      Uri.parse('$apiBaseUrl/dashboards/$dashboardId/widgets/$widgetId'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    return DashboardWidget.fromJson(
        decodeOrThrow(resp) as Map<String, dynamic>);
  }

  Future<void> deleteWidget(int dashboardId, int widgetId) async {
    final resp = await _client.delete(
      Uri.parse('$apiBaseUrl/dashboards/$dashboardId/widgets/$widgetId'),
    );
    decodeOrThrow(resp);
  }

  /// Bulk-update layouts after a drag/resize. Single round-trip.
  Future<void> putLayout(
    int dashboardId,
    List<({int id, WidgetLayout layout})> entries,
  ) async {
    final body = {
      'layouts': [
        for (final e in entries)
          {
            'id': e.id,
            'x': e.layout.x,
            'y': e.layout.y,
            'w': e.layout.w,
            'h': e.layout.h,
          },
      ],
    };
    final resp = await _client.put(
      Uri.parse('$apiBaseUrl/dashboards/$dashboardId/layout'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    decodeOrThrow(resp);
  }

  Future<WidgetData> getWidgetData(int dashboardId, int widgetId) async {
    final resp = await _client.get(
      Uri.parse('$apiBaseUrl/dashboards/$dashboardId/widgets/$widgetId/data'),
    );
    return WidgetData.fromJson(decodeOrThrow(resp) as Map<String, dynamic>);
  }

  // ── Save chat widget to a dashboard ───────────────────────────────────────

  /// Save the widget attached to an AI assistant chat message onto a
  /// dashboard. When the source widget carries `metric_id` /
  /// `metric_params`, the created dashboard widget is `kind:"metric"`
  /// and follows the dashboard's time range; otherwise it is
  /// `kind:"snapshot"` and renders the frozen `data` as-is.
  Future<DashboardWidget> saveChatWidgetToDashboard({
    required int messageId,
    required int dashboardId,
  }) async {
    final resp = await _client.post(
      Uri.parse('$apiBaseUrl/chat/messages/$messageId/save-to-dashboard'),
      headers: _jsonHeaders,
      body: jsonEncode({'dashboard_id': dashboardId}),
    );
    return DashboardWidget.fromJson(
        decodeOrThrow(resp) as Map<String, dynamic>);
  }

  // ── Metric registry ────────────────────────────────────────────────────────

  Future<WidgetMetricRegistry> listMetrics() async {
    final resp = await _client.get(Uri.parse('$apiBaseUrl/widget-metrics'));
    return WidgetMetricRegistry.fromJson(
        decodeOrThrow(resp) as Map<String, dynamic>);
  }

  void dispose() => _client.close();
}
