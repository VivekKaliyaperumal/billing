import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/product_thumb.dart';

/// Port of `src/components/products/ProductCard.tsx`.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.onSelect});
  final Product product;
  final ValueChanged<Product> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final formatPrice = context.watch<SettingsProvider>().formatPrice;
    final outOfStock = product.stock == 0;

    return PressScale(
      enabled: !outOfStock,
      onTap: () => onSelect(product),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(
            opacity: outOfStock ? 0.5 : 1,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: p.border),
                boxShadow: p.shadowSoft,
              ),
              child: Column(
                children: [
                  ProductThumb(image: product.image),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.25, color: p.foreground),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatPrice(product.price),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.primary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${product.stock} in stock',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: product.stock <= 5 ? p.destructive : p.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (product.usageCount > 50)
            Positioned(
              top: -8,
              right: -8,
              child: GradientIconBox(
                icon: LucideIcons.trendingUp,
                gradient: p.gradientAccent,
                size: 28,
                iconSize: 14,
                circle: true,
                shadow: p.shadowAccent,
              ),
            ),
          if (outOfStock)
            Positioned.fill(
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.background.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.destructive.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('Out of Stock',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.destructive)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
