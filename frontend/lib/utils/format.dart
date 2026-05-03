String _addCommas(String intPart) {
  final neg = intPart.startsWith('-');
  final digits = neg ? intPart.substring(1) : intPart;
  final sb = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) sb.write(',');
    sb.write(digits[i]);
  }
  return neg ? '-$sb' : sb.toString();
}

/// Whole-dollar formatting with thousands separators. Example: 1234567 → "1,234,567".
String fmtMoney(num v) => _addCommas(v.toStringAsFixed(0));

/// Two-decimal formatting with thousands separators. Example: 1234.5 → "1,234.50".
String fmtMoneyDecimal(num v) {
  final s = v.toStringAsFixed(2);
  final dot = s.indexOf('.');
  return _addCommas(s.substring(0, dot)) + s.substring(dot);
}
