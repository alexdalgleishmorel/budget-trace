// Exercises the in-memory demo backend end to end: seed load, the metric
// engine behind every default widget, interactive mutations, and the scripted
// chat. Runs without a browser or network.
import 'package:flutter_test/flutter_test.dart';

import 'package:budget_trace/services/demo/demo_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final b = DemoBackend.instance;

  setUpAll(() async {
    await b.ensureLoaded();
  });

  test('seed data loads', () {
    expect(b.listCategories().length, greaterThan(10));
    final txns = b.listTransactions({'limit': '500'});
    expect(txns.length, greaterThan(100));
    expect(txns.first.keys, containsAll(['id', 'date', 'merchant', 'amount', 'category_path']));
  });

  test('me reports AI enabled and a default dashboard', () {
    final me = b.me();
    expect((me['features'] as Map)['ai'], true);
    expect(me['selected_provider_key_available'], true);
    expect(me['last_dashboard_id'], isNotNull);
  });

  test('default dashboard widgets all resolve data', () {
    final dash = b.getDashboard(1);
    final widgets = (dash['widgets'] as List).cast<Map<String, dynamic>>();
    expect(widgets.length, 6);
    for (final w in widgets) {
      final data = b.getWidgetData(1, w['id'] as int);
      expect(data['type'], w['type']);
      expect(data['data'], isA<Map>());
      final payload = data['data'] as Map;
      switch (w['type']) {
        case 'pie':
          expect(payload['slices'], isA<List>());
          expect((payload['slices'] as List), isNotEmpty);
        case 'bar':
          expect((payload['categories'] as List), isNotEmpty);
        case 'timeseries':
          expect((payload['chart'] as Map)['series'], isA<List>());
        case 'query_value':
          expect(payload['value'], isA<num>());
        case 'table':
          expect(payload['columns'], isA<List>());
          expect(payload['rows'], isA<List>());
      }
    }
  });

  test('category filter and date window narrow results', () {
    final all = b.listTransactions({'limit': '500'});
    final grocery =
        b.listTransactions({'limit': '500', 'category_path': 'Living / Grocery'});
    expect(grocery.length, lessThan(all.length));
    expect(grocery.every((t) => t['category_path'] == 'Living / Grocery'), true);

    final uncategorised = b.listTransactions({'limit': '500', 'uncategorised': 'true'});
    expect(uncategorised.every((t) => t['category_id'] == null), true);
  });

  test('interactive mutation: create + delete a category', () {
    final before = b.listCategories().length;
    final created = b.createCategory({'name': 'DemoTest', 'parent_id': null});
    expect(b.listCategories().length, before + 1);
    expect(created['path'], 'DemoTest');
    b.deleteCategory(created['id'] as int);
    expect(b.listCategories().length, before);
  });

  test('creating a metric widget renders live data', () {
    final w = b.createWidget(1, {
      'type': 'treemap',
      'data_source': {'kind': 'metric', 'metric_id': 'spend_by_category', 'params': {}},
      'config': {},
    });
    final data = b.getWidgetData(1, w['id'] as int);
    expect((data['data'] as Map)['nodes'], isA<List>());
    b.deleteWidget(1, w['id'] as int);
  });

  test('scripted chat returns a labelled reply with a widget', () {
    final session = b.createSession();
    final res = b.appendMessage(session['id'] as int, 'how much did I spend on grocery?');
    final assistant = res['assistant_message'] as Map<String, dynamic>;
    expect(assistant['text'], contains('Example reply'));
    expect(assistant['widget'], isNotNull);
    expect((assistant['widget'] as Map)['metric_id'], isNotNull);
    expect(res['cost_usd'], 0.0);
  });

  test('save chat widget to dashboard', () {
    final session = b.createSession();
    final res = b.appendMessage(session['id'] as int, 'show me a category breakdown');
    final msgId = (res['assistant_message'] as Map)['id'] as int;
    final widget = b.saveChatWidget(msgId, 1);
    expect(widget['dashboard_id'], 1);
    final data = b.getWidgetData(1, widget['id'] as int);
    expect(data['data'], isA<Map>());
    b.deleteWidget(1, widget['id'] as int);
  });
}
