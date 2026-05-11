import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_trace/models/dashboard.dart';
import 'package:budget_trace/theme/app_theme.dart';
import 'package:budget_trace/widgets/dash_widgets/widget_card.dart';

// Boots each of the 7 renderers via the WidgetCard's previewData path —
// no backend needed. Confirms each one mounts without throwing on a
// representative payload. Cheap smoke; richer rendering coverage would
// require golden tests which the project does not use elsewhere.

DashboardWidget _fake(String type) => DashboardWidget(
      id: 1, dashboardId: 1, type: type, title: 'test',
      layout: const WidgetLayout(x: 0, y: 0, w: 3, h: 2),
      dataSource: const WidgetDataSource.metric(metricId: 'noop'),
      config: const {},
      createdAt: '', updatedAt: '',
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [BudgetTheme.light]),
      home: Scaffold(
        body: SizedBox(width: 300, height: 200, child: child),
      ),
    );

void main() {
  testWidgets('timeseries widget mounts', (t) async {
    final data = WidgetData(type: 'timeseries', data: {
      'chart': {
        'title': 'Spend',
        'series': [
          {'label': 'A', 'style': 'solid', 'points': [
            {'x': 0, 'y': 1}, {'x': 1, 'y': 2}, {'x': 2, 'y': 1.5},
          ]},
        ],
      },
    });
    await t.pumpWidget(_wrap(WidgetCard(widget: _fake('timeseries'), previewData: data)));
    expect(find.byType(WidgetCard), findsOneWidget);
  });

  testWidgets('bar widget mounts', (t) async {
    final data = WidgetData(type: 'bar', data: {
      'categories': [
        {'label': 'House', 'value': 500.0},
        {'label': 'Living', 'value': 700.0},
      ],
    });
    await t.pumpWidget(_wrap(WidgetCard(widget: _fake('bar'), previewData: data)));
    expect(find.text('House'), findsOneWidget);
  });

  testWidgets('pie widget mounts', (t) async {
    final data = WidgetData(type: 'pie', data: {
      'slices': [
        {'label': 'A', 'value': 10.0},
        {'label': 'B', 'value': 20.0},
      ],
      'total': 30.0,
    });
    await t.pumpWidget(_wrap(WidgetCard(widget: _fake('pie'), previewData: data)));
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('query_value widget mounts', (t) async {
    final data = WidgetData(type: 'query_value', data: {
      'value': 1234.56,
      'format': 'currency',
      'comparison': {
        'value': 1000.0,
        'delta_abs': 234.56,
        'delta_pct': 23.5,
        'label': 'vs. previous',
      },
    });
    await t.pumpWidget(_wrap(WidgetCard(widget: _fake('query_value'), previewData: data)));
    expect(find.text('vs. previous'), findsOneWidget);
  });

  testWidgets('table widget mounts', (t) async {
    final data = WidgetData(type: 'table', data: {
      'columns': [
        {'key': 'merchant', 'label': 'Merchant', 'align': 'left'},
        {'key': 'amount', 'label': 'Amount', 'align': 'right', 'format': 'currency'},
      ],
      'rows': [
        {'merchant': 'Test', 'amount': 12.34},
      ],
    });
    await t.pumpWidget(_wrap(WidgetCard(widget: _fake('table'), previewData: data)));
    expect(find.text('Merchant'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('treemap widget mounts', (t) async {
    final data = WidgetData(type: 'treemap', data: {
      'nodes': [
        {'label': 'A', 'value': 100.0},
        {'label': 'B', 'value': 60.0},
      ],
    });
    await t.pumpWidget(_wrap(WidgetCard(widget: _fake('treemap'), previewData: data)));
    expect(find.byType(WidgetCard), findsOneWidget);
  });

}
