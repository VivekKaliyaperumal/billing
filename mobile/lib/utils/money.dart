/// Money is held as an integer count of minor units (paise, cents) so that
/// totals and balances never pick up floating-point rounding errors.
library;

/// Largest amount accepted from user input: 1 crore in major units.
const maxAmountMinor = 1000000000;

final _amountPattern = RegExp(r'^\d{1,8}(\.\d{1,2})?$');

/// Parses user input such as "60", "60.5" or "1234.56" into minor units.
/// Returns null for anything else, including NaN, Infinity, exponents,
/// negatives, more than two decimals or amounts above [maxAmountMinor].
int? parseAmount(String input) {
  final s = input.trim();
  if (!_amountPattern.hasMatch(s)) return null;
  final parts = s.split('.');
  final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
  final value = int.parse(parts[0]) * 100 + int.parse(fraction);
  return value > maxAmountMinor ? null : value;
}

/// Minor units back to the plain input form: 6000 -> "60", 6050 -> "60.50".
String amountToInput(int minor) {
  final major = minor ~/ 100;
  final rest = minor % 100;
  return rest == 0 ? '$major' : '$major.${rest.toString().padLeft(2, '0')}';
}

/// Minor units as a plain two-decimal number for exports: 123456 -> "1234.56".
String amountToPlain(int minor) {
  final sign = minor < 0 ? '-' : '';
  final abs = minor.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

/// Reads an amount from stored JSON. Data written before amounts moved to
/// integers holds a decimal major-unit value under [legacyKey].
int readAmount(Map<String, dynamic> j, String key, String legacyKey) {
  final minor = j[key];
  if (minor is num) return minor.toInt();
  return ((j[legacyKey] as num) * 100).round();
}
