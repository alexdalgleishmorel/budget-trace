import 'package:flutter/material.dart';

import '../../models/dashboard.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Simple data table for the `table` widget type. Columns and rows come
/// from the server; the widget only knows how to format `currency` /
/// `number` / `percent` values via the column's optional `format` field.
class RecentTableWidgetBody extends StatelessWidget {
  const RecentTableWidgetBody({super.key, required this.data});
  final WidgetData data;

  @override
  Widget build(BuildContext context) {
    final bt = context.bt;
    final columns =
        (data.data['columns'] as List? ?? const []).cast<Map<String, dynamic>>();
    final rows =
        (data.data['rows'] as List? ?? const []).cast<Map<String, dynamic>>();

    if (columns.isEmpty || rows.isEmpty) {
      return Center(
        child: Text('No rows',
            style: TextStyle(fontSize: 12, color: bt.ink4)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: bt.ruleSoft)),
            ),
            child: Row(children: [
              for (final c in columns) _headerCell(bt, c),
            ]),
          ),
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: i.isEven ? Colors.transparent : bt.surface2,
              ),
              child: Row(children: [
                for (final c in columns) _bodyCell(bt, c, rows[i]),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _headerCell(BudgetTheme bt, Map<String, dynamic> c) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          c['label'] as String? ?? c['key'] as String,
          textAlign: _align(c['align'] as String?),
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.6,
            color: bt.ink4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _bodyCell(BudgetTheme bt, Map<String, dynamic> c, Map<String, dynamic> row) {
    final v = row[c['key']];
    final fmt = c['format'] as String?;
    String text;
    if (v == null) {
      text = '—';
    } else if (fmt == 'currency') {
      text = '\$${fmtMoneyDecimal((v as num).toDouble())}';
    } else if (fmt == 'number') {
      text = fmtMoney((v as num).toDouble());
    } else {
      text = v.toString();
    }
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: _align(c['align'] as String?),
          style: TextStyle(
            fontSize: 12,
            color: bt.ink2,
            fontFeatures: fmt == 'currency' || fmt == 'number'
                ? const [FontFeature.tabularFigures()]
                : null,
          ),
        ),
      ),
    );
  }

  TextAlign _align(String? a) {
    if (a == 'right') return TextAlign.right;
    if (a == 'center') return TextAlign.center;
    return TextAlign.left;
  }
}
