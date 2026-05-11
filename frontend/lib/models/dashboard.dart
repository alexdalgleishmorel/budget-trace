/// Models that mirror the backend's dashboards / widgets / widget-metrics
/// wire format. Snake_case JSON on the wire → camelCase fields here, via
/// manual `fromJson` constructors (matches the existing transaction /
/// category model style).
library;

import 'package:flutter/widgets.dart';

import '../widgets/timeseries_chart.dart';
import 'chart_spec.dart';

/// Polymorphic widget payload emitted by the Insights AI. Mirrors the
/// backend's `WidgetSpec`. The shape of [data] matches what
/// `widget_metrics.resolve_metric_data` returns for each widget [type],
/// so the same renderer handles AI output and dashboard data uniformly.
///
/// When the AI was able to express the answer as a curated metric,
/// [metricId] / [metricParams] capture the re-runnable query: saving
/// the widget to a dashboard creates a `kind:"metric"` widget that
/// follows the dashboard's time range. Otherwise the answer is a frozen
/// snapshot and [fallbackReason] explains why no metric fit.
class WidgetPayload {
  const WidgetPayload({
    required this.type,
    required this.title,
    required this.data,
    this.metricId,
    this.metricParams,
    this.fallbackReason,
  });

  final String type;
  final String title;
  final Map<String, dynamic> data;
  final String? metricId;
  final Map<String, dynamic>? metricParams;
  final String? fallbackReason;

  /// True when the widget cannot be re-run on a dashboard — i.e. the
  /// answer would need to be served as frozen bytes. The chat-side
  /// "Save to dashboard" flow uses this to badge the resulting widget.
  bool get isSnapshot => metricId == null;

  factory WidgetPayload.fromJson(Map<String, dynamic> j) => WidgetPayload(
        type: j['type'] as String,
        title: j['title'] as String? ?? '',
        data: Map<String, dynamic>.from(j['data'] as Map),
        metricId: j['metric_id'] as String?,
        metricParams: j['metric_params'] is Map
            ? Map<String, dynamic>.from(j['metric_params'] as Map)
            : null,
        fallbackReason: j['fallback_reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'data': data,
        if (metricId != null) 'metric_id': metricId,
        if (metricParams != null) 'metric_params': metricParams,
        if (fallbackReason != null) 'fallback_reason': fallbackReason,
      };

  /// Treat the payload as a [WidgetData] so it can flow into
  /// `WidgetCard.previewData`. Chat widgets are always rendered as
  /// snapshots in the transcript (the chat is the historical view).
  WidgetData asData() =>
      WidgetData(type: type, data: data, isSnapshot: true);
}

/// Time window applied to every widget on a dashboard. Presets roll with
/// the calendar (server-resolved each request); `custom` honours
/// `customStart` / `customEnd` (both ISO YYYY-MM-DD).
class DashboardTimeRange {
  const DashboardTimeRange({
    required this.preset,
    this.customStart,
    this.customEnd,
  });

  final String preset;
  final String? customStart;
  final String? customEnd;

  static const fallback = DashboardTimeRange(preset: 'last_3_months');

  factory DashboardTimeRange.fromJson(Map<String, dynamic> j) =>
      DashboardTimeRange(
        preset: j['preset'] as String? ?? 'last_3_months',
        customStart: j['custom_start'] as String?,
        customEnd: j['custom_end'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'preset': preset,
        if (customStart != null) 'custom_start': customStart,
        if (customEnd != null) 'custom_end': customEnd,
      };

  /// Stable cache key used by [WidgetCard.revalidationKey] so widgets
  /// re-fetch when the dashboard's range shifts.
  String get cacheKey => '$preset|${customStart ?? ''}|${customEnd ?? ''}';
}

class DashboardSummary {
  const DashboardSummary({
    required this.id,
    required this.name,
    required this.timeRange,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final DashboardTimeRange timeRange;
  final String createdAt;
  final String updatedAt;

  factory DashboardSummary.fromJson(Map<String, dynamic> j) => DashboardSummary(
        id: j['id'] as int,
        name: j['name'] as String,
        timeRange: DashboardTimeRange.fromJson(
            (j['time_range'] as Map<String, dynamic>?) ?? const {}),
        createdAt: j['created_at'] as String,
        updatedAt: j['updated_at'] as String,
      );
}

class Dashboard {
  const Dashboard({
    required this.id,
    required this.name,
    required this.timeRange,
    required this.createdAt,
    required this.updatedAt,
    required this.widgets,
  });

  final int id;
  final String name;
  final DashboardTimeRange timeRange;
  final String createdAt;
  final String updatedAt;
  final List<DashboardWidget> widgets;

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        id: j['id'] as int,
        name: j['name'] as String,
        timeRange: DashboardTimeRange.fromJson(
            (j['time_range'] as Map<String, dynamic>?) ?? const {}),
        createdAt: j['created_at'] as String,
        updatedAt: j['updated_at'] as String,
        widgets: (j['widgets'] as List? ?? const [])
            .map((w) => DashboardWidget.fromJson(w as Map<String, dynamic>))
            .toList(),
      );
}

class WidgetLayout {
  const WidgetLayout({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final int x;
  final int y;
  final int w;
  final int h;

  factory WidgetLayout.fromJson(Map<String, dynamic> j) => WidgetLayout(
        x: j['x'] as int,
        y: j['y'] as int,
        w: j['w'] as int,
        h: j['h'] as int,
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  WidgetLayout copyWith({int? x, int? y, int? w, int? h}) => WidgetLayout(
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
      );
}

/// Frontend-side data-source descriptor. Either a curated metric (live,
/// follows the dashboard's time range) or a snapshot (frozen bytes lifted
/// off a chat answer; ignores the dashboard's time range). Mirrors the
/// JSON shape stored in `widgets.data_source_json` server-side; the
/// renderer never branches on this — it dispatches on the widget `type`
/// and the data shape returned from
/// `GET /dashboards/:id/widgets/:wid/data`. The `is_snapshot` flag in
/// that response is what triggers the chrome's "Snapshot" badge.
class WidgetDataSource {
  const WidgetDataSource.metric({
    required this.metricId,
    this.params = const {},
  }) : kind = 'metric';

  const WidgetDataSource.snapshot()
      : kind = 'snapshot',
        metricId = null,
        params = const {};

  final String kind; // 'metric' | 'snapshot'
  final String? metricId;
  final Map<String, dynamic> params;

  factory WidgetDataSource.fromJson(Map<String, dynamic> j) {
    final kind = j['kind'] as String;
    if (kind == 'metric') {
      return WidgetDataSource.metric(
        metricId: j['metric_id'] as String,
        params: Map<String, dynamic>.from(
          (j['params'] as Map<String, dynamic>?) ?? const {},
        ),
      );
    }
    return const WidgetDataSource.snapshot();
  }

  Map<String, dynamic> toJson() {
    if (kind == 'metric') {
      return {'kind': 'metric', 'metric_id': metricId, 'params': params};
    }
    return {'kind': 'snapshot'};
  }

  bool get isMetric => kind == 'metric';
  bool get isSnapshot => kind == 'snapshot';
}

class DashboardWidget {
  const DashboardWidget({
    required this.id,
    required this.dashboardId,
    required this.type,
    required this.title,
    required this.layout,
    required this.dataSource,
    required this.config,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int dashboardId;
  final String type;
  final String title;
  final WidgetLayout layout;
  final WidgetDataSource dataSource;
  final Map<String, dynamic> config;
  final String createdAt;
  final String updatedAt;

  factory DashboardWidget.fromJson(Map<String, dynamic> j) => DashboardWidget(
        id: j['id'] as int,
        dashboardId: j['dashboard_id'] as int,
        type: j['type'] as String,
        title: j['title'] as String,
        layout: WidgetLayout.fromJson(j['layout'] as Map<String, dynamic>),
        dataSource:
            WidgetDataSource.fromJson(j['data_source'] as Map<String, dynamic>),
        config:
            Map<String, dynamic>.from((j['config'] as Map<String, dynamic>?) ?? const {}),
        createdAt: j['created_at'] as String,
        updatedAt: j['updated_at'] as String,
      );

  DashboardWidget copyWith({
    String? title,
    WidgetLayout? layout,
    WidgetDataSource? dataSource,
    Map<String, dynamic>? config,
  }) =>
      DashboardWidget(
        id: id,
        dashboardId: dashboardId,
        type: type,
        title: title ?? this.title,
        layout: layout ?? this.layout,
        dataSource: dataSource ?? this.dataSource,
        config: config ?? this.config,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// Static description of a curated metric. Returned by `GET /widget-metrics`.
/// `widgetTypes` is the set of widget types this metric can populate; the
/// drawer filters compatible metrics for the selected widget type. The
/// `paramsSchema` is rendered to a form by the drawer.
class WidgetMetricDef {
  const WidgetMetricDef({
    required this.id,
    required this.label,
    required this.description,
    required this.widgetTypes,
    required this.paramsSchema,
    required this.usesTimeRange,
  });

  final String id;
  final String label;
  final String description;
  final List<String> widgetTypes;
  final List<Map<String, dynamic>> paramsSchema;

  /// When false (e.g. `spend_forecast`), the dashboard's time range does
  /// not affect this widget — the metric has its own implicit window.
  final bool usesTimeRange;

  factory WidgetMetricDef.fromJson(Map<String, dynamic> j) => WidgetMetricDef(
        id: j['id'] as String,
        label: j['label'] as String,
        description: j['description'] as String,
        widgetTypes: (j['widget_types'] as List).cast<String>(),
        paramsSchema: (j['params_schema'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        usesTimeRange: j['uses_time_range'] as bool? ?? true,
      );
}

class WidgetMetricRegistry {
  const WidgetMetricRegistry({
    required this.metrics,
    required this.minSizes,
    required this.timeRangePresets,
  });

  final List<WidgetMetricDef> metrics;
  final Map<String, WidgetLayout> minSizes; // type → minimum (w, h)
  final List<String> timeRangePresets;

  factory WidgetMetricRegistry.fromJson(Map<String, dynamic> j) {
    final raw = (j['widget_min_sizes'] as Map<String, dynamic>?) ?? const {};
    final mins = <String, WidgetLayout>{};
    raw.forEach((type, val) {
      final list = (val as List).cast<int>();
      mins[type] = WidgetLayout(x: 0, y: 0, w: list[0], h: list[1]);
    });
    return WidgetMetricRegistry(
      metrics: (j['metrics'] as List)
          .map((m) => WidgetMetricDef.fromJson(m as Map<String, dynamic>))
          .toList(),
      minSizes: mins,
      timeRangePresets:
          (j['time_range_presets'] as List? ?? const []).cast<String>(),
    );
  }

  WidgetMetricDef? metricById(String id) =>
      metrics.where((m) => m.id == id).cast<WidgetMetricDef?>().firstWhere(
            (m) => true,
            orElse: () => null,
          );
}

/// Discriminated union of widget data shapes returned by
/// `GET /dashboards/:id/widgets/:wid/data`. Frontend renderers branch on
/// `type` (== `widget.type`) and read the matching payload — never on the
/// data_source kind. [isSnapshot] is true when the underlying widget is
/// frozen bytes (saved from a chat answer that no curated metric could
/// express); the chrome shows a "Snapshot" badge and disables refresh
/// when true.
class WidgetData {
  const WidgetData({
    required this.type,
    required this.data,
    this.isSnapshot = false,
    this.viaChat = false,
  });
  final String type;
  final Map<String, dynamic> data;
  final bool isSnapshot;

  /// True when the widget originated from the Insights chat
  /// "Save to dashboard…" flow. Drives a subtle green footer on the
  /// dashboard chrome so the user can tell its provenance.
  final bool viaChat;

  factory WidgetData.fromJson(Map<String, dynamic> j) => WidgetData(
        type: j['type'] as String,
        data: Map<String, dynamic>.from(j['data'] as Map<String, dynamic>),
        isSnapshot: j['is_snapshot'] as bool? ?? false,
        viaChat: j['via_chat'] as bool? ?? false,
      );

  // Type-specific accessors. Cast-shaped — keeps the renderer files small.

  ChartSpec asChart() =>
      ChartSpec.fromJson(data['chart'] as Map<String, dynamic>);

  List<({String label, double value})> asCategoricalItems(String key) {
    return (data[key] as List)
        .map((e) {
          final m = e as Map<String, dynamic>;
          return (label: m['label'] as String, value: (m['value'] as num).toDouble());
        })
        .toList();
  }

  double? get queryValue =>
      data['value'] is num ? (data['value'] as num).toDouble() : null;

  String get queryValueFormat => data['format'] as String? ?? 'number';

  /// Optional per-period rate label — e.g. `"month"` → rendered as
  /// "$999 / month" beside the headline number. Only set on metrics
  /// whose value is genuinely rate-shaped (currently `average_per_period`).
  String? get queryUnit => data['unit'] as String?;

  Map<String, dynamic>? get queryComparison =>
      data['comparison'] is Map<String, dynamic>
          ? data['comparison'] as Map<String, dynamic>
          : null;

  List<double>? get querySparkline {
    final s = data['sparkline'];
    if (s is List) return s.map((v) => (v as num).toDouble()).toList();
    return null;
  }

  // Convenience to render the chart at flexible (parent-bound) height.
  /// Discards [TimeseriesChart.height] argument so it fills its parent.
  /// Hides the chart's internal title — the surrounding [WidgetCard]
  /// titlebar already shows it.
  Widget? buildChartFlex() {
    if (data['chart'] is! Map) return null;
    return asChart().buildChart(height: null, showTitle: false);
  }
}

// Re-exported to keep call sites importing one file.
typedef ChartSeriesPoint = ChartPoint;
