import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';

/// Wraps the existing [TimeseriesChart] for the dashboard grid. Reuses the
/// same painter and visuals — the only difference is `height: null` so the
/// chart fills the grid cell instead of taking a fixed 240dp.
class TimeseriesWidgetBody extends StatelessWidget {
  const TimeseriesWidgetBody({super.key, required this.data});
  final WidgetData data;

  @override
  Widget build(BuildContext context) {
    final chart = data.buildChartFlex();
    if (chart == null) {
      return Center(
        child: Text('No chart data',
            style: TextStyle(fontSize: 12, color: context.bt.ink4)),
      );
    }
    return chart;
  }
}
