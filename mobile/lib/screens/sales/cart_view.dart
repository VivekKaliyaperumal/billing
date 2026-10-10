import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Empty cart state from `Cart.tsx`.
class EmptyCart extends StatefulWidget {
  const EmptyCart({super.key});

  @override
  State<EmptyCart> createState() => _EmptyCartState();
}

class _EmptyCartState extends State<EmptyCart> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DashedBox(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          FadeTransition(
            opacity: Tween(begin: 1.0, end: 0.5).animate(_pulse),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: p.secondary, shape: BoxShape.circle),
              child: Icon(LucideIcons.shoppingCart, size: 40, color: p.mutedForeground),
            ),
          ),
          const SizedBox(height: 20),
          Text('Cart is empty', style: display(20, color: p.foreground)),
          const SizedBox(height: 8),
          Text(
            'Select products from the list to add them here',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: p.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// Filled cart from `Cart.tsx`.
class CartView extends StatelessWidget {
  const CartView({
    super.key,
    required this.items,
    required this.onUpdateQuantity,
    required this.onRemove,
    required this.onCheckout,
    required this.onCreditSale,
    this.listMaxHeight = 350,
  });

  final List<CartItem> items;
  final void Function(String productId, int quantity) onUpdateQuantity;
  final ValueChanged<String> onRemove;
  final VoidCallback onCheckout;
  final VoidCallback onCreditSale;
  final double listMaxHeight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    final total = items.fold(0.0, (s, i) => s + i.subtotal);
    final itemCount = items.fold(0, (s, i) => s + i.quantity);

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: p.border),
        boxShadow: p.shadowMedium,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: p.gradientPrimary),
            child: Row(
              children: [
                const Icon(LucideIcons.shoppingCart, size: 20, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Current Sale', style: display(18, color: Colors.white))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$itemCount items',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: listMaxHeight),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => CartItemTile(
                item: items[i],
                onUpdateQuantity: onUpdateQuantity,
                onRemove: onRemove,
              ),
            ),
          ),
          Divider(color: p.border),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Subtotal ($itemCount items)', style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                    Text(formatPrice(total), style: TextStyle(fontSize: 14, color: p.mutedForeground)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.foreground)),
                    Text(formatPrice(total),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.primary)),
                  ],
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Complete Sale',
                  icon: LucideIcons.receipt,
                  height: 48,
                  expand: true,
                  shadow: p.shadowMedium,
                  onPressed: onCheckout,
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'Credit Sale (Pay Later)',
                  icon: LucideIcons.userPlus,
                  variant: ButtonVariant.outline,
                  color: p.accent,
                  height: 48,
                  expand: true,
                  onPressed: onCreditSale,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Port of `src/components/sales/CartItem.tsx`.
class CartItemTile extends StatelessWidget {
  const CartItemTile({super.key, required this.item, required this.onUpdateQuantity, required this.onRemove});
  final CartItem item;
  final void Function(String productId, int quantity) onUpdateQuantity;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    final id = item.product.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.secondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.foreground)),
                Text('${formatPrice(item.product.price)} each',
                    style: TextStyle(fontSize: 12, color: p.mutedForeground)),
              ],
            ),
          ),
          AppIconButton(
            icon: LucideIcons.minus,
            size: 32,
            color: p.foreground,
            onPressed: item.quantity <= 1 ? null : () => onUpdateQuantity(id, item.quantity - 1),
          ),
          SizedBox(
            width: 32,
            child: Text('${item.quantity}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.foreground)),
          ),
          AppIconButton(
            icon: LucideIcons.plus,
            size: 32,
            color: p.foreground,
            onPressed: () => onUpdateQuantity(id, item.quantity + 1),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 70),
            child: Text(formatPrice(item.subtotal),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.primary)),
          ),
          AppIconButton(icon: LucideIcons.x, size: 32, onPressed: () => onRemove(id)),
        ],
      ),
    );
  }
}
