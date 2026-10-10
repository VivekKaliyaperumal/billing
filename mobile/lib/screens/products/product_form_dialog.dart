import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/common.dart';

/// Port of `src/components/admin/ProductForm.tsx`, same validation messages.
class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({super.key, this.product, required this.onSubmit});
  final Product? product;
  final void Function(String name, double price, int stock, String? image) onSubmit;

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _price = TextEditingController(text: widget.product != null ? _num(widget.product!.price) : '');
  late final _stock = TextEditingController(text: widget.product?.stock.toString() ?? '');
  late final _image = TextEditingController(text: widget.product?.image ?? '');
  Map<String, String> _errors = {};

  // JS `price.toString()`: 60 -> "60", 60.5 -> "60.5".
  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    _image.dispose();
    super.dispose();
  }

  bool _validate() {
    final e = <String, String>{};
    final name = _name.text;
    if (name.trim().isEmpty) {
      e['name'] = 'Product name is required';
    } else if (name.length > 100) {
      e['name'] = 'Name must be less than 100 characters';
    }
    final price = double.tryParse(_price.text);
    if (price == null || price <= 0) e['price'] = 'Enter a valid price greater than 0';
    final stock = int.tryParse(_stock.text);
    if (stock == null || stock < 0) e['stock'] = 'Enter a valid stock quantity (0 or more)';
    if (_image.text.length > 500) e['image'] = 'Image URL must be less than 500 characters';
    setState(() => _errors = e);
    return e.isEmpty;
  }

  void _submit() {
    if (!_validate()) return;
    final image = _image.text.trim();
    widget.onSubmit(
      _name.text.trim(),
      double.parse(_price.text),
      int.parse(_stock.text),
      image.isEmpty ? null : image,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final symbol = context.watch<SettingsProvider>().settings.currencySymbol;
    final editing = widget.product != null;

    return AppDialog(
      title: Row(children: [
        GradientIconBox(
          icon: LucideIcons.package,
          gradient: p.gradientPrimary,
          size: 40,
          iconSize: 20,
          radius: AppRadius.xl,
        ),
        const SizedBox(width: 8),
        Text(editing ? 'Edit Product' : 'Add New Product'),
      ]),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            AppTextField(label: 'Product Name *', controller: _name, hint: 'e.g., Milk 1L', error: _errors['name']),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Price ($symbol) *',
                    controller: _price,
                    hint: '0.00',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    error: _errors['price'],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(
                    label: 'Stock Quantity *',
                    controller: _stock,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    error: _errors['stock'],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AppTextField(
              label: 'Image URL (optional)',
              controller: _image,
              hint: 'https://example.com/image.jpg',
              keyboardType: TextInputType.url,
              error: _errors['image'],
            ),
            const SizedBox(height: 32),
            Row(children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: ButtonVariant.outline,
                  height: 48,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: editing ? 'Save Changes' : 'Add Product',
                  height: 48,
                  expand: true,
                  onPressed: _submit,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
