import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'format.dart';
import 'money.dart';

/// Same columns as the web History page's "Export CSV".
String buildSalesCsv(List<Sale> sales) => [
      ['Date', 'Items', 'Total'].map(csvField).join(','),
      ...sales.map((s) => [
            dateCsv.format(s.date),
            s.items.map((i) => '${i.product.name} x${i.quantity}').join('; '),
            amountToPlain(s.total),
          ].map(csvField).join(',')),
    ].join('\r\n');

/// Escapes one CSV field (RFC 4180) and neutralises spreadsheet formulas, so
/// a product named `=HYPERLINK(...)` cannot run when the file is opened.
String csvField(String value) {
  var v = value;
  if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
  if (v.contains(RegExp('[",\r\n]'))) v = '"${v.replaceAll('"', '""')}"';
  return v;
}

/// Writes the CSV to a temp file and opens the share sheet
/// (mobile stand-in for the browser download).
Future<void> exportSalesCsv(List<Sale> sales) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/sales-export-${dateFile.format(DateTime.now())}.csv');
  await file.writeAsString(buildSalesCsv(sales));
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')]));
}
