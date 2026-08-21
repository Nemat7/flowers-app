import 'package:flutter/material.dart';

import '../../api/models/shop.dart';
import '../../common/widgets/app_network_image.dart';
import '../../shop/shop_screen.dart';
import '../../theme/colors.dart';
import '../../theme/formatters.dart';

/// Карточка магазина (макет v5 01-home, `.shop`): обложка 150px radius 12,
/// круглое сердечко справа вверху, зелёный бейдж «Наш магазин» слева внизу,
/// строка названия с рейтингом и мета-строка с профилем магазина справа.
/// Закрытый магазин — grayscale + тёмная плашка «Закрыто» (состояния,
/// которого в макете нет, но без него карточка врёт о доступности).
class ShopCard extends StatelessWidget {
  const ShopCard({required this.shop, super.key});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShopScreen(shopId: shop.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(),
                  const Positioned(top: 10, right: 10, child: _HeartButton()),
                  if (!shop.isOpen)
                    const Positioned(
                      left: 10,
                      bottom: 10,
                      child: _Badge(
                        label: 'Закрыто',
                        color: AppColors.closedBadge,
                      ),
                    )
                  else if (shop.isOwn)
                    const Positioned(
                      left: 10,
                      bottom: 10,
                      child: _Badge(
                        label: 'Наш магазин',
                        color: AppColors.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 9, 2, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    shop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (shop.ratingCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '★ ${formatRating(shop.rating)}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 3, 2, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _metaLine(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (shop.kind != null && shop.kind!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    shop.kind!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover() {
    final image = AppNetworkImage(
      url: shop.coverImage,
      height: double.infinity,
      placeholderSeed: shop.id,
      placeholderIcon: Icons.storefront,
    );
    if (shop.isOpen) return image;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(
        Colors.grey,
        BlendMode.saturation,
      ),
      child: image,
    );
  }

  /// «35–45 мин · Доставка от 10 с.»; если тарифа нет — мин. сумма заказа.
  String _metaLine() {
    return <String>[
      if (shop.deliveryTimeRange != null) shop.deliveryTimeRange!,
      if (shop.deliveryFeeFrom != null)
        'Доставка от ${formatSomoni(shop.deliveryFeeFrom!)}'
      else
        'мин. заказ ${formatSomoni(shop.minOrder)}',
    ].join(' · ');
  }
}

/// Круглое сердечко поверх фото (визуально; избранное — следующий этап).
class _HeartButton extends StatelessWidget {
  const _HeartButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.favorite_border_rounded,
        size: 16,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// Плашка поверх обложки: зелёная «Наш магазин» или тёмная «Закрыто».
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
