import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/receipt_pdf.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// Port of `src/components/sales/SaleReceipt.tsx`.
class ReceiptDialog extends StatelessWidget {
  const ReceiptDialog({super.key, required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settingsProvider = context.watch<SettingsProvider>();
    final formatPrice = settingsProvider.formatPrice;
    final muted = TextStyle(fontSize: 14, color: p.mutedForeground);

    return AppDialog(
      title: Row(children: [
        GradientIconBox(
          icon: LucideIcons.check,
          gradient: p.gradientSuccess,
          size: 48,
          circle: true,
          shadow: p.shadowMedium,
        ),
        const SizedBox(width: 12),
        const Text('Sale Complete!'),
      ]),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.secondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Receipt #${sale.id.substring(0, 8)}', style: muted),
                  const SizedBox(height: 4),
                  Text(dateTimeLocal.format(sale.date), style: muted),
                  const SizedBox(height: 4),
                  Text(settingsProvider.settings.shopName,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.foreground)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final item in sale.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: item.product.name,
                          style: TextStyle(fontWeight: FontWeight.w500, color: p.foreground)),
                      TextSpan(text: '  × ${item.quantity}', style: TextStyle(color: p.mutedForeground)),
                    ])),
                  ),
                  Text(formatPrice(item.subtotal),
                      style: TextStyle(fontWeight: FontWeight.w500, color: p.foreground)),
                ]),
              ),
            Divider(color: p.border),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.foreground)),
                Text(formatPrice(sale.total),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.primary)),
              ],
            ),
            if (sale.isPending == true) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: p.accent.withValues(alpha: 0.2)),
                ),
                child: Text('Credit Sale - Payment Pending',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.accent)),
              ),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: AppButton(
                  label: 'Print',
                  icon: LucideIcons.printer,
                  variant: ButtonVariant.outline,
                  expand: true,
                  onPressed: () async {
                    try {
                      await printReceipt(sale, settingsProvider.settings);
                    } catch (_) {
                      if (context.mounted) {
                        showToast(context,
                            title: 'Error', description: 'Could not open the print dialog', destructive: true);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Done',
                  icon: LucideIcons.receipt,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
