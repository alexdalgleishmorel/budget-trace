/// Wire-format chart spec returned by the backend's `present_to_user` tool.
///
/// Shape mirrors `backend/src/budget_trace_backend/models.py`. The backend
/// emits snake_case JSON; the parsers here translate to Dart-native camelCase.
/// Maps cleanly onto [TimeseriesChart] constructor args at render time.
library;

import 'package:flutter/material.dart';

import '../widgets/timeseries_chart.dart';

class ChartSpec {
  ChartSpec({
    required this.title,
    required this.series,
    this.yAxisLabel,
    this.xAxisLabel,
    this.xTickLabels,
  });

  final String title;
  final String? yAxisLabel;
  final String? xAxisLabel;
  final List<String>? xTickLabels;
  final List<ChartSeriesSpec> series;

  factory ChartSpec.fromJson(Map<String, dynamic> json) => ChartSpec(
        title: json['title'] as String,
        yAxisLabel: json['y_axis_label'] as String?,
        xAxisLabel: json['x_axis_label'] as String?,
        xTickLabels: (json['x_tick_labels'] as List?)?.map((e) => e as String).toList(),
        series: (json['series'] as List)
            .map((s) => ChartSeriesSpec.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  /// Convert into a renderable [TimeseriesChart]. Pass `height: null` to
  /// have the chart flex to fill its parent (e.g. inside a dashboard grid
  /// cell that already provides bounded height via Expanded/SizedBox).
  /// Pass `showTitle: false` when the surrounding chrome already shows
  /// the title (the `WidgetCard` titlebar does, so the dashboard path
  /// always wants this).
  Widget buildChart({double? height = 240, bool showTitle = true}) {
    return TimeseriesChart(
      title: title,
      series: series.map((s) => s.toChartSeries()).toList(),
      xAxisLabel: xAxisLabel,
      yAxisLabel: yAxisLabel,
      xTickLabels: xTickLabels,
      height: height,
      showTitle: showTitle,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        if (yAxisLabel != null) 'y_axis_label': yAxisLabel,
        if (xAxisLabel != null) 'x_axis_label': xAxisLabel,
        if (xTickLabels != null) 'x_tick_labels': xTickLabels,
        'series': series.map((s) => s.toJson()).toList(),
      };
}

class ChartSeriesSpec {
  ChartSeriesSpec({
    required this.label,
    required this.points,
    this.style = LineStyle.solid,
  });

  final String label;
  final LineStyle style;
  final List<ChartPoint> points;

  factory ChartSeriesSpec.fromJson(Map<String, dynamic> json) => ChartSeriesSpec(
        label: json['label'] as String,
        style: (json['style'] as String? ?? 'solid') == 'dashed'
            ? LineStyle.dashed
            : LineStyle.solid,
        points: (json['points'] as List)
            .map((p) => ChartPoint(
                  (p['x'] as num).toDouble(),
                  (p['y'] as num).toDouble(),
                ))
            .toList(),
      );

  ChartSeries toChartSeries() => ChartSeries(
        label: label,
        points: points,
        style: style,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'style': style == LineStyle.dashed ? 'dashed' : 'solid',
        'points': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
      };
}
