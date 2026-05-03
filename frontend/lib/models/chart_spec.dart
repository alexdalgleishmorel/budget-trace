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

  /// Convert into a renderable [TimeseriesChart].
  Widget buildChart({double height = 240}) {
    return TimeseriesChart(
      title: title,
      series: series.map((s) => s.toChartSeries()).toList(),
      xAxisLabel: xAxisLabel,
      yAxisLabel: yAxisLabel,
      xTickLabels: xTickLabels,
      height: height,
    );
  }
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
}
