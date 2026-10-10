import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Product image, or the `Package` icon on a secondary→muted gradient.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, this.image, this.size = 64});
  final String? image;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final placeholder = Icon(LucideIcons.package, size: size / 2, color: p.mutedForeground);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.secondary, p.muted],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null || image!.isEmpty
          ? placeholder
          : Image.network(
              image!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
