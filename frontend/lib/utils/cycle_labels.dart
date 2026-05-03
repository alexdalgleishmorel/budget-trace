/// Returns the list of "Month YYYY" labels for the cycle dropdown.
///
/// Today this is just the 12 months ending in the current month — same window
/// the backend's seed populates. A future Phase 2.5 could derive this from
/// actual data (e.g. the min/max dates returned by `/transactions`), but for
/// the MVP a fixed sliding window matches user expectations.
library;

import 'date_range.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

List<String> cycleLabelsForLast(int months, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final out = <String>[];
  for (int i = months - 1; i >= 0; i--) {
    final d = DateTime(n.year, n.month - i, 1);
    out.add('${_monthNames[d.month - 1]} ${d.year}');
  }
  return out;
}

/// "March 2025" → DateRange covering 2025-03-01..2025-03-31.
DateRange? cycleRangeForLabel(String label) {
  final parts = label.split(' ');
  if (parts.length != 2) return null;
  final monthIndex = _monthNames.indexOf(parts[0]);
  if (monthIndex < 0) return null;
  final year = int.tryParse(parts[1]);
  if (year == null) return null;
  final month = monthIndex + 1;
  final start = DateTime(year, month, 1);
  final end = DateTime(year, month + 1, 0); // last day of `month`
  return DateRange(start: _iso(start), end: _iso(end));
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
