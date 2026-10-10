import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import 'format.dart';

/// Same CSV as the web History page's "Export CSV".
String buildSalesCsv(List<Sale> sales) => [
      ['Date', 'Items', 'Total'].join(','),
      ...sales.map((s) => [
            dateCsv.format(s.date),
            s.items.map((i) => '${i.product.name} x${i.quantity}').join('; '),
            s.total.toStringAsFixed(2),
          ].join(',')),
    ].join('\n');

/// Writes the CSV to a temp file and opens the share sheet
/// (mobile stand-in for the browser download).
Future<void> exportSalesCsv(List<Sale> sales) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/sales-export-${dateFile.format(DateTime.now())}.csv');
  await file.writeAsString(buildSalesCsv(sales));
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')]));
}
