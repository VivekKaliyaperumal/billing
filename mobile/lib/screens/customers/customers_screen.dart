import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/customer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';

/// Port of `src/pages/CustomersPage.tsx` (credit ledger).
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _query = '';
  String? _expanded;

  void _openAddCustomer() {
    showAppDialog<void>(context, (_) => const _AddCustomerDialog());
  }

  void _openPayment(String customerId) {
    showAppDialog<void>(context, (_) => _PaymentDialog(customerId: customerId));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final provider = context.watch<CustomerProvider>();
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    final customers = provider.customers;
    final q = _query.toLowerCase();
    final filtered = customers.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(_query)).toList();
    final withDues = customers.where((c) => c.pendingAmount > 0).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      child: FadeIn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              icon: LucideIcons.users,
              gradient: p.gradientAccent,
              shadow: p.shadowAccent,
              title: 'Customers',
              subtitle: '${customers.length} registered customers',
              action: AppButton(
                label: 'Add Customer',
                icon: LucideIcons.plus,
                height: 44,
                shadow: p.shadowMedium,
                onPressed: _openAddCustomer,
              ),
            ),
            const SizedBox(height: 32),
            AppCard(
              stripe: p.gradientAccent,
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(LucideIcons.wallet, size: 16, color: p.mutedForeground),
                  const SizedBox(width: 8),
                  Text('Total Pending',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.mutedForeground)),
                ]),
                const SizedBox(height: 12),
                Text(formatPrice(provider.totalPendingAmount),
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: p.accent)),
                const SizedBox(height: 4),
                Text('$withDues customers with dues', style: TextStyle(fontSize: 14, color: p.mutedForeground)),
              ]),
            ),
            const SizedBox(height: 32),
            AppSearchField(
              hint: 'Search customers by name or phone...',
              large: false,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 24),
            if (filtered.isEmpty)
              DashedBox(
                child: Column(children: [
                  Icon(LucideIcons.users, size: 48, color: p.mutedForeground),
                  const SizedBox(height: 16),
                  Text('No customers found', style: TextStyle(color: p.mutedForeground)),
                ]),
              )
            else
              for (final c in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CustomerCard(
                    customer: c,
                    expanded: _expanded == c.id,
                    formatPrice: formatPrice,
                    onToggle: () => setState(() => _expanded = _expanded == c.id ? null : c.id),
                    onPay: () => _openPayment(c.id),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.expanded,
    required this.formatPrice,
    required this.onToggle,
    required this.onPay,
  });

  final Customer customer;
  final bool expanded;
  final String Function(double) formatPrice;
  final VoidCallback onToggle;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasDues = customer.pendingAmount > 0;
    return AppCard(
      shadow: p.shadowSoft,
      leftBorderColor: hasDues ? p.accent : null,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.secondary, shape: BoxShape.circle),
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.foreground),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(customer.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: p.foreground)),
                Row(children: [
                  Icon(LucideIcons.phone, size: 12, color: p.mutedForeground),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(customer.phone,
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 20, color: p.mutedForeground),
          ]),
        ),
        if (hasDues) ...[
          const SizedBox(height: 12),
          Row(children: [
            const SizedBox(width: 64),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pending', style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                Text(formatPrice(customer.pendingAmount),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.accent)),
              ]),
            ),
            AppButton(
              label: 'Pay',
              icon: LucideIcons.creditCard,
              variant: ButtonVariant.outline,
              color: p.success,
              height: 36,
              onPressed: onPay,
            ),
          ]),
        ],
        if (expanded && customer.transactions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Divider(color: p.border),
          const SizedBox(height: 16),
          Text('Transaction History',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.mutedForeground)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 192),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: customer.transactions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final t = customer.transactions[customer.transactions.length - 1 - i];
                final isCredit = t.type == TransactionType.credit;
                final color = isCredit ? p.accent : p.success;
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: p.secondary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14), children: [
                        TextSpan(text: isCredit ? 'Credit' : 'Payment', style: TextStyle(color: color)),
                        TextSpan(text: '  - ${t.description}', style: TextStyle(color: p.mutedForeground)),
                      ])),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${isCredit ? '+' : '-'}${formatPrice(t.amount)}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color)),
                      Text(dateLocal.format(t.date), style: TextStyle(fontSize: 12, color: p.mutedForeground)),
                    ]),
                  ]),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog();

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text;
    if (name.trim().isEmpty || _phone.text.trim().isEmpty) {
      showToast(context, title: 'Error', description: 'Please fill all fields', destructive: true);
      return;
    }
    context.read<CustomerProvider>().addCustomer(name: name, phone: _phone.text);
    Navigator.of(context).pop();
    showToast(context, title: 'Customer added', description: '$name has been added.');
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: const Text('Add New Customer'),
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppTextField(label: 'Name', controller: _name, hint: 'Customer name'),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Phone Number',
              controller: _phone,
              hint: 'Phone number',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            AppButton(label: 'Add Customer', expand: true, onPressed: _submit),
          ]),
        ),
      );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.customerId});
  final String customerId;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text);
    if (amount == null || amount <= 0) {
      showToast(context, title: 'Error', description: 'Please enter a valid amount', destructive: true);
      return;
    }
    context.read<CustomerProvider>().addPayment(widget.customerId, amount, 'Payment received');
    final formatted = context.read<SettingsProvider>().formatPrice(amount);
    Navigator.of(context).pop();
    showToast(context, title: 'Payment recorded', description: 'Payment of $formatted received.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppDialog(
      title: const Text('Record Payment'),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTextField(
            label: 'Payment Amount',
            controller: _amount,
            hint: 'Enter amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Record Payment',
            icon: LucideIcons.creditCard,
            gradient: p.gradientSuccess,
            expand: true,
            onPressed: _submit,
          ),
        ]),
      ),
    );
  }
}
