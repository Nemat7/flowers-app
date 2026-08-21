import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models/product.dart';
import '../theme/colors.dart';
import 'cart_controller.dart';

/// Добавить товар в корзину с соблюдением правила «один заказ = один магазин».
/// При конфликте магазинов показывает диалог подтверждения очистки.
Future<void> addToCartWithConfirm(
  BuildContext context,
  Product product, {
  String? shopName,
}) async {
  final cart = context.read<CartController>();
  final result = cart.tryAdd(product, shopName: shopName);
  if (result == CartAddResult.added) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} — в корзине'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Начать новый заказ?'),
      content: Text(
        'В корзине товары магазина «${cart.shopName ?? 'другой магазин'}». '
        'Очистить корзину и начать новый заказ из «${shopName ?? 'этого магазина'}»?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: AppColors.accent),
          child: const Text('Очистить и добавить'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    context.read<CartController>().replaceWith(product, shopName: shopName);
  }
}
