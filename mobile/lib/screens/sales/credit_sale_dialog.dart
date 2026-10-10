import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/customer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/common.dart';

/// Credit Sale dialog from SalesPage.tsx. [onConfirm] returns true when the
/// sale was recorded, which closes the dialog.
class CreditSaleDialog extends StatefulWidget {
  const CreditSaleDialog({super.key, required this.total, required this.onConfirm});
  final int total; // minor units
  final Future<bool> Function(String? customerId, String name, String phone) onConfirm;

  @override
  State<CreditSaleDialog> createState() => _CreditSaleDialogState();
}

class _CreditSaleDialogState extends State<CreditSaleDialog> {
  String? _customerId;
  bool _saving = false;
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final close = await widget.onConfirm(_customerId, _name.text, _phone.text);
    if (!mounted) return;
    if (close) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final customers = context.watch<CustomerProvider>().customers;
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    final locked = _customerId != null;

    return AppDialog(
      title: Row(children: [
        Icon(LucideIcons.userPlus, size: 20, color: p.accent),
        const SizedBox(width: 8),
        Flexible(child: Text('Credit Sale - ${formatPrice(widget.total)}')),
      ]),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Select Existing Customer'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: AppSelect<String>(
                  value: _customerId,
                  height: 48,
                  placeholder: 'Choose customer',
                  options: [for (final c in customers) SelectOption(c.id, '${c.name} - ${c.phone}')],
                  onChanged: (v) => setState(() => _customerId = v),
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 8),
                AppIconButton(
                  icon: LucideIcons.x,
                  size: 48,
                  outlined: true,
                  tooltip: 'Clear selected customer',
                  onPressed: () => setState(() => _customerId = null),
                ),
              ],
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Divider(color: p.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('OR ADD NEW', style: TextStyle(fontSize: 12, color: p.mutedForeground)),
              ),
              Expanded(child: Divider(color: p.border)),
            ]),
            const SizedBox(height: 16),
            AppTextField(controller: _name, hint: 'Customer name', enabled: !locked),
            const SizedBox(height: 12),
            AppTextField(
              controller: _phone,
              hint: 'Phone number',
              enabled: !locked,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            AppButton(
              gradient: p.gradientAccent,
              shadow: p.shadowAccent,
              height: 48,
              expand: true,
              label: _saving ? 'Saving...' : 'Confirm Credit Sale',
              onPressed: _saving ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}
