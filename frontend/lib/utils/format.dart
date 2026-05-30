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

/// Currency prefix for displayed budget amounts. All transaction/budget
/// figures are in Canadian dollars; "CA$" disambiguates from USD.
const String kMoneySymbol = 'CA\$';

/// Whole-dollar CAD amount. Example: 1234567 → "CA$1,234,567".
String money(num v) => '$kMoneySymbol${fmtMoney(v)}';

/// Two-decimal CAD amount. Example: 1234.5 → "CA$1,234.50".
String moneyDecimal(num v) => '$kMoneySymbol${fmtMoneyDecimal(v)}';
