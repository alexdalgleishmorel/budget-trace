/// Scripted, transparently-mocked chat for the demo build. The real Insights
/// AI runs a backend orchestrator + tool loop that can't exist statically, so
/// these replies are pre-written. Every reply is explicitly labelled as an
/// example so visitors are never misled into thinking a live model answered.
library;

import 'demo_metrics.dart';

/// Leading marker prepended to every assistant reply. Rendered as a markdown
/// blockquote in the transcript.
const String _disclaimer =
    '> _Example reply — this demo\'s AI is mocked, not a live model. '
    'Run the app locally (Docker) with your own API key for real answers._';

/// Help text for `GET /chat/help`, also led by the mock disclaimer.
const String demoChatHelpText = '''
$_disclaimer

**This is a demo.** The assistant's answers here are pre-written examples — they
illustrate what Insights looks like, but no live model is running.

In the real app, Insights can:

- **Analyse spending** — totals, trends, category breakdowns, top merchants, and
  forecasts, rendered as charts you can save to a dashboard.
- **Edit your data** — create/rename/recolour categories, recategorise
  transactions, and bulk-rename merchants, all from chat.

Try asking about *grocery spending*, *top merchants*, a *category breakdown*, or a
*forecast* to see example widgets.
''';

class ScriptedReply {
  ScriptedReply(this.text, [this.widget]);

  final String text;

  /// WidgetPayload-shaped map ({type, title, data, metric_id, metric_params})
  /// or null for a text-only reply.
  final Map<String, dynamic>? widget;
}

Map<String, dynamic> _widget(
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
  String type,
  String title,
  String metricId,
  Map<String, dynamic> params,
) {
  // Full-window range so the example widgets are richly populated. Metrics
  // that ignore the dashboard window (forecast) resolve their own anyway.
  final range = resolveTimeRange('last_12_months');
  return {
    'type': type,
    'title': title,
    'data': resolveMetricData(cats, txns, metricId, params, type, range),
    'metric_id': metricId,
    'metric_params': params,
  };
}

ScriptedReply buildScriptedReply(
  String userText,
  List<Map<String, dynamic>> cats,
  List<Map<String, dynamic>> txns,
) {
  final t = userText.toLowerCase();
  String body(String s) => '$_disclaimer\n\n$s';

  if (t.contains('grocery') || t.contains('food') || t.contains('groceries')) {
    return ScriptedReply(
      body('Here\'s your **grocery spend by month** over the past year. Spending '
          'tends to climb around the holidays and settle again in spring — a '
          'common seasonal pattern.'),
      _widget(cats, txns, 'timeseries', 'Grocery spend by month', 'spend_over_time',
          {'rollup_period': 'month', 'category_path': 'Grocery'}),
    );
  }
  if (t.contains('merchant') || t.contains('where') || t.contains('who')) {
    return ScriptedReply(
      body('These are your **top merchants** by total spend. The largest few '
          'usually account for most of the outflow — worth a look if you want to '
          'trim spending.'),
      _widget(cats, txns, 'pie', 'Top merchants', 'top_merchants', {'limit': 8}),
    );
  }
  if (t.contains('forecast') || t.contains('predict') || t.contains('next month') ||
      t.contains('project')) {
    return ScriptedReply(
      body('Here\'s a simple **spend forecast** for the next few months, projected '
          'from your recent monthly average. The dashed line is the projection.'),
      _widget(cats, txns, 'timeseries', 'Spend forecast', 'spend_forecast',
          {'horizon_months': 3, 'method': 'trailing_avg'}),
    );
  }
  if (t.contains('category') || t.contains('breakdown') || t.contains('split') ||
      t.contains('where does')) {
    return ScriptedReply(
      body('Here\'s how your spending **breaks down by category**. House and Living '
          'usually dominate; tap a slice to compare proportions.'),
      _widget(cats, txns, 'pie', 'Spend by category', 'spend_by_category', {}),
    );
  }
  if (t.contains('total') || t.contains('how much') || t.contains('spent') ||
      t.contains('spend')) {
    return ScriptedReply(
      body('Here\'s your **total spend** for the last 12 months, with a comparison '
          'to the previous period.'),
      _widget(cats, txns, 'query_value', 'Total spend', 'total_spend',
          {'compare_to_previous': true}),
    );
  }

  // Fallback — still useful, still clearly an example.
  return ScriptedReply(
    body('In the real app I\'d analyse your transactions to answer that. For this '
        'demo, here\'s an example **category breakdown** — try asking about '
        '*grocery spending*, *top merchants*, or a *forecast* for more examples.'),
    _widget(cats, txns, 'bar', 'Spend by category', 'spend_by_category', {}),
  );
}
