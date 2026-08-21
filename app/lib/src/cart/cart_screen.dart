import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../checkout/checkout_screen.dart';
import '../common/widgets/app_network_image.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';
import 'cart_controller.dart';

/// Плавающая пилюля «Корзина · X с.» (макет v5 02-shop): чёрная,
/// с зелёным счётчиком позиций. Показывается на витрине, когда
/// в корзине есть товары этого магазина.
class CartPill extends StatelessWidget {
  const CartPill({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    if (cart.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 12,
      child: Material(
        color: Colors.black,
        borderRadius: BorderRadius.circular(999),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.28),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CartScreen()),
          ),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      height: 22,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${cart.totalCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Корзина',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${formatSomoni(cart.subtotal)} →',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Экран корзины (макет v5 06-cart): магазин, позиции с серым степпером,
/// итоги, чёрная пилюля «Оформить · X с.».
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Корзина')),
      body: cart.isEmpty
          ? const _EmptyCart()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              children: [
                if (cart.shopName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            cart.shopName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (var i = 0; i < cart.items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  _CartItemTile(item: cart.items[i]),
                ],
                const SizedBox(height: 22),
                Container(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
                _TotalLine(
                  label: 'Товары (${cart.totalCount})',
                  value: formatSomoni(cart.subtotal),
                ),
                const SizedBox(height: 3),
                const _TotalLine(
                  label: 'Доставка',
                  value: 'рассчитается при оформлении',
                  valueColor: AppColors.textSecondary,
                ),
              ],
            ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.of(context).padding.bottom + 14,
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CheckoutScreen(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Оформить'),
                      Text(formatSomoni(cart.subtotal)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shopping_bag_outlined,
              size: 56, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text('Корзина пуста',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'Выберите букет в любом магазине',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 64,
            height: 64,
            child: AppNetworkImage(
              url: item.product.photo,
              height: 64,
              placeholderSeed: item.product.id,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                formatSomoni(item.lineTotal),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Серый степпер-пилюля (макет 06-cart).
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              _stepBtn(
                // На единице минус удаляет позицию — то же, что корзина
                // делала кнопкой удаления.
                item.qty > 1 ? Icons.remove : Icons.delete_outline,
                () => item.qty > 1
                    ? cart.decrement(item.product.id)
                    : cart.remove(item.product.id),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${item.qty}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _stepBtn(Icons.add, () => cart.increment(item.product.id)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 17, color: AppColors.textSecondary),
      ),
    );
  }
}
