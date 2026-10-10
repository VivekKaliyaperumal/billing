import 'package:intl/intl.dart';

/// Formats minor units with Indian grouping and exactly two decimals,
/// e.g. 123456789 -> "12,34,567.89". Integer-only, so no rounding drift.
String formatIndian(int minor) {
  final negative = minor < 0;
  final abs = minor.abs();
  final intPart = (abs ~/ 100).toString();
  final fraction = (abs % 100).toString().padLeft(2, '0');
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
  return '${negative ? '-' : ''}$grouped.$fraction';
}

/// "1 item", "3 items". [many] defaults to [one] + "s".
String plural(int count, String one, [String? many]) => '$count ${count == 1 ? one : (many ?? '${one}s')}';

/// Plain number for chart axis ticks, like JS `${value}`.
String formatAxis(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// Equivalents of the web app's date output (en-IN browser locale).
final dateTimeLocal = DateFormat('dd-MMM-yyyy, h:mm a'); // unambiguous, e.g. 10-Oct-2026
final dateLocal = DateFormat('dd-MMM-yyyy');
final timeHm = DateFormat('HH:mm');
final dateTable = DateFormat('dd-MMM-yyyy HH:mm');
final dateCsv = DateFormat('yyyy-MM-dd HH:mm');
final dateFile = DateFormat('yyyy-MM-dd');
final monthShort = DateFormat('MMM');
