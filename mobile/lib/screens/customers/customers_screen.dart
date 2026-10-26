import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/money.dart';
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

  Future<void> _openAddCustomer() {
    return showAppDialog<void>(context, (_) => const _CustomerFormDialog(), dismissible: false);
  }

  Future<void> _openEdit(Customer customer) {
    return showAppDialog<void>(context, (_) => _CustomerFormDialog(customer: customer), dismissible: false);
  }

  Future<void> _confirmDelete(Customer customer) {
    return showAppDialog<void>(
      context,
      (dialogCtx) => AppDialog(
        showClose: false,
        title: const Text('Delete Customer?'),
        description: Text('Delete "${customer.name}" and their transaction history? This cannot be undone.'),
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            AppButton(label: 'Cancel', variant: ButtonVariant.outline, onPressed: () => Navigator.of(dialogCtx).pop()),
            const SizedBox(width: 8),
            AppButton(
              label: 'Delete',
              variant: ButtonVariant.destructive,
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                final deleted = await context.read<CustomerProvider>().deleteCustomer(customer.id);
                if (deleted && mounted) {
                  showToast(context, title: 'Customer deleted', description: '${customer.name} has been removed.');
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openPayment(String customerId) {
    return showAppDialog<void>(context, (_) => _PaymentDialog(customerId: customerId), dismissible: false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final provider = context.watch<CustomerProvider>();
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    // Only the owner deletes customers.
    final canDelete = context.watch<AuthProvider>().isOwner;
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
              subtitle: plural(customers.length, 'registered customer'),
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
                Text('${plural(withDues, 'customer')} with dues', style: TextStyle(fontSize: 14, color: p.mutedForeground)),
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
                    onEdit: () => _openEdit(c),
                    onDelete: canDelete ? () => _confirmDelete(c) : null,
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
    required this.onEdit,
    this.onDelete,
  });

  final Customer customer;
  final bool expanded;
  final String Function(int) formatPrice;
  final VoidCallback onToggle;
  final VoidCallback onPay;
  final VoidCallback onEdit;

  /// Null hides the button (cashiers).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasDues = customer.pendingAmount > 0;
    return AppCard(
      shadow: p.shadowSoft,
      leftBorderColor: hasDues ? p.accent : null,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PressScale(
          onTap: onToggle,
          semanticLabel: '${customer.name}, ${expanded ? 'hide' : 'show'} details',
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
              height: 44,
              onPressed: onPay,
            ),
          ]),
        ],
        if (expanded) ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            AppButton(label: 'Edit', icon: LucideIcons.squarePen, variant: ButtonVariant.outline, height: 44, onPressed: onEdit),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: hasDues ? 'Clear the pending amount before deleting' : 'Delete customer',
                child: AppButton(
                  label: 'Delete',
                  icon: LucideIcons.trash2,
                  variant: ButtonVariant.outline,
                  color: p.destructive,
                  height: 44,
                  onPressed: hasDues ? null : onDelete,
                ),
              ),
            ],
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

/// Adds a customer, or edits one when [customer] is given.
class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({this.customer});
  final Customer? customer;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final customers = context.read<CustomerProvider>();
    final editing = widget.customer;
    final error = customers.validateDetails(_name.text, _phone.text, excludingId: editing?.id);
    if (error != null) {
      showToast(context, title: 'Error', description: error, destructive: true);
      return;
    }
    setState(() => _saving = true);
    final saved = editing != null
        ? await customers.updateDetails(editing.id, name: _name.text, phone: _phone.text)
        : (await customers.addCustomer(name: _name.text, phone: _phone.text)) != null;
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop();
    showToast(context,
        title: editing != null ? 'Customer updated' : 'Customer added',
        description: '${_name.text.trim()} has been ${editing != null ? 'updated' : 'added'}.');
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: Text(widget.customer != null ? 'Edit Customer' : 'Add New Customer'),
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
            AppButton(
              label: _saving ? 'Saving...' : (widget.customer != null ? 'Save Changes' : 'Add Customer'),
              expand: true,
              height: 48,
              onPressed: _saving ? null : _submit,
            ),
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
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final customers = context.read<CustomerProvider>();
    final formatPrice = context.read<SettingsProvider>().formatPrice;
    final pending = customers.byId(widget.customerId)?.pendingAmount ?? 0;
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      showToast(context, title: 'Error', description: 'Please enter a valid amount', destructive: true);
      return;
    }
    if (amount > pending) {
      showToast(context,
          title: 'Error', description: 'Amount is more than the pending ${formatPrice(pending)}', destructive: true);
      return;
    }
    setState(() => _saving = true);
    final saved = await customers.addPayment(widget.customerId, amount, 'Payment received');
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    final formatted = formatPrice(amount);
    Navigator.of(context).pop();
    showToast(context, title: 'Payment recorded', description: 'Payment of $formatted received.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pending = context.watch<CustomerProvider>().byId(widget.customerId)?.pendingAmount ?? 0;
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    return AppDialog(
      title: const Text('Record Payment'),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Pending: ${formatPrice(pending)}', style: TextStyle(fontSize: 14, color: p.mutedForeground)),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Payment Amount',
            controller: _amount,
            hint: 'Enter amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: _saving ? 'Saving...' : 'Record Payment',
            icon: LucideIcons.creditCard,
            gradient: p.gradientSuccess,
            expand: true,
            height: 48,
            onPressed: _saving ? null : _submit,
          ),
        ]),
      ),
    );
  }
}
