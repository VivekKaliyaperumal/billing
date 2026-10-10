import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/models.dart';
import 'format.dart';

/// Mobile stand-in for the web app's `window.print()`: renders the receipt
/// (same content as the dialog) and opens the system print sheet.
Future<void> printReceipt(Sale sale, AppSettings settings) async {
  // Bundled Inter covers ₹ / € / £, which the built-in PDF font lacks.
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));
  String price(int v) => '${settings.currencySymbol}${formatIndian(v)}';

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      theme: pw.ThemeData.withFont(base: font, bold: bold),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(settings.shopName,
              textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Receipt #${sale.id.substring(0, 8)}', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(dateTimeLocal.format(sale.date), style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
          for (final item in sale.items)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(children: [
                pw.Expanded(
                  child: pw.Text('${item.product.name} x ${item.quantity}', style: const pw.TextStyle(fontSize: 9)),
                ),
                pw.Text(price(item.subtotal), style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
          pw.Divider(),
          pw.Row(children: [
            pw.Expanded(child: pw.Text('Total', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
            pw.Text(price(sale.total), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ]),
          if (sale.isPending == true) ...[
            pw.SizedBox(height: 6),
            pw.Text('Credit Sale - Payment Pending', style: const pw.TextStyle(fontSize: 9)),
          ],
        ],
      ),
    ),
  );

  await Printing.layoutPdf(
    name: 'receipt-${sale.id.substring(0, 8)}',
    onLayout: (_) => doc.save(),
  );
}
