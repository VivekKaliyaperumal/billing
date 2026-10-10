import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/app_database.dart';
import '../../models/models.dart';
import '../../providers/cart_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/checkout_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/common.dart';
import '../../widgets/toast.dart';
import 'cart_view.dart';
import 'credit_sale_dialog.dart';
import 'product_card.dart';
import 'receipt_dialog.dart';

/// Port of `src/pages/SalesPage.tsx`. On phones the cart opens from a
/// floating "Current Sale" bar; on wide screens it sits beside the grid.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  static const _wideBreakpoint = 900.0;
  String _query = '';

  /// True while a sale is being saved; blocks a second tap from
  /// recording the same cart twice.
  bool _busy = false;

  void _selectProduct(Product product) {
    final current = context.read<ProductProvider>().byId(product.id);
    final maxStock = current?.stock ?? product.stock;
    if (!context.read<CartProvider>().add(product, maxStock)) {
      showToast(context,
          title: 'Stock limit reached',
          description: 'Only $maxStock items available for ${product.name}',
          destructive: true);
    }
  }

  void _updateQuantity(String productId, int quantity) {
    if (quantity < 1) return;
    final current = context.read<ProductProvider>().byId(productId);
    if (current == null) return;
    if (quantity > current.stock) {
      showToast(context,
          title: 'Stock limit reached', description: 'Only ${current.stock} items available', destructive: true);
      return;
    }
    context.read<CartProvider>().setQuantity(productId, quantity);
  }

  void _showReceipt(Sale sale) => showAppDialog<void>(context, (_) => ReceiptDialog(sale: sale));

  CheckoutService get _checkoutService => CheckoutService(
        db: context.read<AppDatabase>(),
        cart: context.read<CartProvider>(),
        products: context.read<ProductProvider>(),
        history: context.read<SalesHistoryProvider>(),
        customers: context.read<CustomerProvider>(),
      );

  void _showCartChanged(List<String> changes) {
    showToast(context,
        title: 'Cart updated - please review', description: changes.join('\n'), destructive: true);
  }

  Future<T> _whileBusy<T>(Future<T> Function() action) async {
    setState(() => _busy = true);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkout() async {
    if (_busy || context.read<CartProvider>().isEmpty) return;
    final result = await _whileBusy(_checkoutService.checkout);
    if (!mounted) return;
    switch (result) {
      case CheckoutCompleted(:final sale):
        _showReceipt(sale);
        showToast(context,
            title: 'Sale completed!', description: 'Total: ${context.read<SettingsProvider>().formatPrice(sale.total)}');
      case CheckoutCartChanged(:final changes):
        _showCartChanged(changes);
      case CheckoutCustomerError() || CheckoutFailed():
        break; // Customer errors can't occur for cash; save failures are already shown.
    }
  }

  Future<void> _creditSale() async {
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;
    await showAppDialog<void>(
      context,
      (_) => CreditSaleDialog(total: cart.total, onConfirm: _confirmCreditSale),
      dismissible: false,
    );
  }

  /// Returns true when the dialog should close: the sale was recorded, or
  /// the cart changed and must be reviewed before trying again.
  Future<bool> _confirmCreditSale(String? selectedId, String name, String phone) async {
    if (_busy) return false;
    final result = await _whileBusy(
      () => _checkoutService.creditCheckout(selectedId: selectedId, name: name, phone: phone),
    );
    if (!mounted) return false;
    switch (result) {
      case CheckoutCompleted(:final sale):
        // Open the receipt once the credit dialog has closed, then the toast
        // on top of it.
        final message = '${context.read<SettingsProvider>().formatPrice(sale.total)} added to customer credit';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showReceipt(sale);
          showToast(context, title: 'Credit sale recorded', description: message);
        });
        return true;
      case CheckoutCartChanged(:final changes):
        _showCartChanged(changes);
        return true;
      case CheckoutCustomerError(:final message):
        showToast(context, title: 'Error', description: message, destructive: true);
        return false;
      case CheckoutFailed():
        return false;
    }
  }

  Widget _cart({double listMaxHeight = 350}) {
    final cart = context.watch<CartProvider>();
    if (cart.isEmpty) return const EmptyCart();
    return CartView(
      items: cart.items,
      listMaxHeight: listMaxHeight,
      busy: _busy,
      onUpdateQuantity: _updateQuantity,
      onRemove: context.read<CartProvider>().remove,
      onCheckout: _checkout,
      onCreditSale: _creditSale,
    );
  }

  Future<void> _openCartSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (sheetCtx) => Consumer<CartProvider>(
        builder: (_, cart, _) {
          if (cart.isEmpty) {
            // Close only if this sheet is still the top route: after checkout
            // the receipt dialog may already be on top, and a plain pop()
            // would close the receipt instead.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!sheetCtx.mounted) return;
              final route = ModalRoute.of(sheetCtx);
              if (route != null && route.isCurrent) Navigator.of(sheetCtx).pop();
            });
            return const SizedBox.shrink();
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: CartView(
                items: cart.items,
                listMaxHeight: MediaQuery.of(sheetCtx).size.height * 0.4,
                onUpdateQuantity: _updateQuantity,
                onRemove: cart.remove,
                onCheckout: () {
                  Navigator.of(sheetCtx).pop();
                  unawaited(_checkout());
                },
                onCreditSale: () {
                  Navigator.of(sheetCtx).pop();
                  unawaited(_creditSale());
                },
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final products = context.watch<ProductProvider>();
    final cart = context.watch<CartProvider>();
    final displayed = _query.trim().isNotEmpty ? products.searchProducts(_query) : products.getMostUsedProducts(12);

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= _wideBreakpoint;
      final gridWidth = wide ? c.maxWidth - 420 - 24 - 32 : c.maxWidth - 32;
      final columns = gridWidth >= 640 ? 4 : (gridWidth >= 480 ? 3 : 2);

      final productsSection = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(hint: 'Search products...', onChanged: (v) => setState(() => _query = v)),
          const SizedBox(height: 24),
          Row(children: [
            GradientIconBox(
              icon: LucideIcons.sparkles,
              gradient: p.gradientAccent,
              size: 32,
              iconSize: 16,
              radius: AppRadius.xl,
            ),
            const SizedBox(width: 8),
            Text(_query.isNotEmpty ? 'Search Results' : 'Most Used Products',
                style: display(20, color: p.foreground)),
          ]),
          const SizedBox(height: 24),
          if (displayed.isEmpty)
            DashedBox(
              child: Center(
                child: Text(_query.isNotEmpty ? 'No products found' : 'No products available',
                    style: TextStyle(color: p.mutedForeground)),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              clipBehavior: Clip.none,
              itemCount: displayed.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: 214,
              ),
              itemBuilder: (_, i) => ProductCard(product: displayed[i], onSelect: _selectProduct),
            ),
        ],
      );

      if (wide) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16).copyWith(top: 24, bottom: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: productsSection),
              const SizedBox(width: 24),
              SizedBox(width: 420, child: _cart()),
            ],
          ),
        );
      }

      return Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 24, 16, cart.isEmpty ? 24 : 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                productsSection,
                if (cart.isEmpty) ...[const SizedBox(height: 24), const EmptyCart()],
              ],
            ),
          ),
          if (!cart.isEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _CartBar(itemCount: cart.itemCount, total: cart.total, onTap: _openCartSheet),
            ),
        ],
      );
    });
  }
}

/// Floating summary bar that opens the cart sheet on phones.
class _CartBar extends StatelessWidget {
  const _CartBar({required this.itemCount, required this.total, required this.onTap});
  final int itemCount;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    return PressScale(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: p.gradientPrimary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: p.shadowGlow,
        ),
        child: Row(children: [
          const Icon(LucideIcons.shoppingCart, size: 20, color: Colors.white),
          const SizedBox(width: 12),
          Text('Current Sale', style: display(18, color: Colors.white)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(plural(itemCount, 'item'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white)),
          ),
          const Spacer(),
          Text(formatPrice(total),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevronUp, size: 20, color: Colors.white),
        ]),
      ),
    );
  }
}
