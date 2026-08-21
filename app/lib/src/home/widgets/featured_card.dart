import 'package:flutter/material.dart';

import '../../api/models/product.dart';
import '../../catalog/product_screen.dart';
import '../../common/widgets/app_network_image.dart';
import '../../theme/colors.dart';
import '../../theme/formatters.dart';

/// Карточка ленты «Наше фирменное» (макет v5 01-home, `.fcard`):
/// фото 150×100 radius 12, зелёный бейдж «Наш бренд» слева сверху,
/// круглое сердечко справа, название 13.5/700 и цена серым.
class FeaturedCard extends StatelessWidget {
  const FeaturedCard({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductScreen(product: product),
        ),
      ),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppNetworkImage(
                      url: product.photo,
                      height: 100,
                      placeholderSeed: product.id,
                    ),
                    const Positioned(
                      left: 8,
                      top: 8,
                      child: _BrandBadge(),
                    ),
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: _HeartCircle(size: 28, icon: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatSomoni(product.price),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Наш бренд',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Круглое сердечко поверх фото (визуально; избранное — следующий этап).
class _HeartCircle extends StatelessWidget {
  const _HeartCircle({required this.size, required this.icon});

  final double size;
  final double icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.favorite_border_rounded,
        size: icon,
        color: AppColors.textPrimary,
      ),
    );
  }
}
