import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/currency.dart';
import '../utils/product_image.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.baseUrl,
  });

  final PosexProduct product;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = resolveProductImageUrl(baseUrl, product.productImages);
    final stockColor = product.isLowStock
        ? const Color(0xFFDC2626)
        : const Color(0xFF059669);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 72,
                height: 72,
                color: theme.colorScheme.surfaceContainerHighest,
                child: imageUrl == null
                    ? const Icon(Icons.inventory_2_outlined, size: 32)
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                          Icons.broken_image_outlined,
                          size: 28,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.itemCode,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (product.barcode != null && product.barcode!.isNotEmpty)
                    Text(
                      product.barcode!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (product.categoryName != null &&
                      product.categoryName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        product.categoryName!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: stockColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Stock ${product.stock.toStringAsFixed(product.stock % 1 == 0 ? 0 : 2)} ${product.unit}',
                          style: TextStyle(
                            color: stockColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatLkr(product.sellingPrice),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFF97316),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
