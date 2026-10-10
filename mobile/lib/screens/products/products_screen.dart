import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/common.dart';
import '../../widgets/product_thumb.dart';
import '../../widgets/toast.dart';
import 'product_form_dialog.dart';

/// Port of `src/pages/AdminPage.tsx` + `ProductTable.tsx`. The web table
/// becomes a list on mobile; edit/delete are always visible (no hover).
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _query = '';

  Future<void> _openForm([Product? product]) {
    return showAppDialog<void>(
      context,
      (_) => ProductFormDialog(
        product: product,
        onSubmit: (name, price, stock, image) async {
          final products = context.read<ProductProvider>();
          final saved = product != null
              ? await products.updateProduct(product.id, name: name, price: price, stock: stock, image: image)
              : await products.addProduct(name: name, price: price, stock: stock, image: image);
          if (saved && mounted) {
            showToast(context,
                title: product != null ? 'Product updated' : 'Product added',
                description: product != null ? '$name has been updated.' : '$name has been added to your inventory.');
          }
          return saved;
        },
      ),
      dismissible: false,
    );
  }

  Future<void> _confirmDelete(Product product) {
    return showAppDialog<void>(
      context,
      (dialogCtx) => AppDialog(
        showClose: false,
        title: const Text('Delete Product?'),
        description: Text('Are you sure you want to delete "${product.name}"? This action cannot be undone.'),
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Cancel',
                variant: ButtonVariant.outline,
                onPressed: () => Navigator.of(dialogCtx).pop(),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Delete',
                variant: ButtonVariant.destructive,
                onPressed: () async {
                  Navigator.of(dialogCtx).pop();
                  final deleted = await context.read<ProductProvider>().deleteProduct(product.id);
                  if (deleted && mounted) {
                    showToast(context,
                        title: 'Product deleted', description: 'The product has been removed from your inventory.');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = context.watch<ProductProvider>().products;
    final filtered = _query.isNotEmpty
        ? all.where((x) => x.name.toLowerCase().contains(_query.toLowerCase())).toList()
        : all;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      child: FadeIn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              icon: LucideIcons.package,
              gradient: p.gradientPrimary,
              title: 'Product Management',
              subtitle: '${plural(all.length, 'product')} in inventory',
              action: AppButton(
                label: 'Add Product',
                icon: LucideIcons.plus,
                height: 44,
                shadow: p.shadowMedium,
                onPressed: _openForm,
              ),
            ),
            const SizedBox(height: 32),
            AppSearchField(hint: 'Search products...', onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 24),
            if (filtered.isEmpty)
              DashedBox(
                child: Column(children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(color: p.secondary, shape: BoxShape.circle),
                    child: Icon(LucideIcons.package, size: 40, color: p.mutedForeground),
                  ),
                  const SizedBox(height: 20),
                  Text('No products yet', style: display(20, color: p.foreground)),
                  const SizedBox(height: 8),
                  Text('Add your first product to get started',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                ]),
              )
            else
              _ProductList(products: filtered, onEdit: _openForm, onDelete: _confirmDelete),
          ],
        ),
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.products, required this.onEdit, required this.onDelete});
  final List<Product> products;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    final head = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.mutedForeground);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: p.secondary.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              const SizedBox(width: 60),
              Expanded(child: Text('Product Name', style: head)),
              Text('Price / Stock', style: head),
              const SizedBox(width: 104), // edit + delete buttons
            ]),
          ),
          for (var i = 0; i < products.length; i++) ...[
            if (i > 0) Divider(color: p.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                ProductThumb(image: products[i].image, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(products[i].name,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.foreground)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(LucideIcons.trendingUp, size: 14, color: p.mutedForeground),
                        const SizedBox(width: 6),
                        Text('${products[i].usageCount}', style: TextStyle(fontSize: 13, color: p.mutedForeground)),
                      ]),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatPrice(products[i].price),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.primary)),
                    const SizedBox(height: 4),
                    _StockPill(stock: products[i].stock),
                  ],
                ),
                const SizedBox(width: 8),
                AppIconButton(
                  icon: LucideIcons.squarePen,
                  tooltip: 'Edit ${products[i].name}',
                  onPressed: () => onEdit(products[i]),
                ),
                AppIconButton(
                  icon: LucideIcons.trash2,
                  tooltip: 'Delete ${products[i].name}',
                  onPressed: () => onDelete(products[i]),
                  color: p.mutedForeground,
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill({required this.stock});
  final int stock;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = stock == 0 ? p.destructive : (stock <= 5 ? p.warning : p.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
      child: Text('$stock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
