import 'package:intl/intl.dart';

/// Same as JS `amount.toLocaleString('en-IN', {min/max fraction digits: 2})`:
/// Indian grouping (12,34,567.89) with exactly two decimals.
String formatIndian(double amount) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  String grouped;
  if (intPart.length <= 3) {
    grouped = intPart;
  } else {
    final last3 = intPart.substring(intPart.length - 3);
    var rest = intPart.substring(0, intPart.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    grouped = '${groups.join(',')},$last3';
  }
  return '${negative ? '-' : ''}$grouped.${parts[1]}';
}

/// Plain number for chart axis ticks, like JS `${value}`.
String formatAxis(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// Equivalents of the web app's date output (en-IN browser locale).
final dateTimeLocal = DateFormat('d/M/yyyy, h:mm:ss a'); // toLocaleString()
final dateLocal = DateFormat('d/M/yyyy'); // toLocaleDateString()
final timeHm = DateFormat('HH:mm');
final dateTable = DateFormat('MMM dd, yyyy HH:mm');
final dateCsv = DateFormat('yyyy-MM-dd HH:mm');
final dateFile = DateFormat('yyyy-MM-dd');
final monthShort = DateFormat('MMM');
