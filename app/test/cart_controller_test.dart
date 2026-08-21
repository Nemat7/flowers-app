import 'package:flowers_client/src/api/models/product.dart';
import 'package:flowers_client/src/cart/cart_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product(int id, int shopId, String price) => Product(
      id: id,
      shopId: shopId,
      name: 'Товар $id',
      price: double.parse(price),
      isAvailable: true,
    );

void main() {
  group('CartController', () {
    test('добавление товара и накопление количества', () {
      final cart = CartController();
      expect(cart.tryAdd(_product(1, 10, '450.00'), shopName: 'Лотос'),
          CartAddResult.added);
      expect(cart.tryAdd(_product(1, 10, '450.00')), CartAddResult.added);
      expect(cart.tryAdd(_product(2, 10, '85.50')), CartAddResult.added);

      expect(cart.shopId, 10);
      expect(cart.shopName, 'Лотос');
      expect(cart.totalCount, 3);
      expect(cart.qtyOf(1), 2);
      expect(cart.qtyOf(2), 1);
      expect(cart.subtotal, closeTo(985.50, 0.001));
    });

    test('правило одного магазина: чужой товар отклоняется без side-эффектов',
        () {
      final cart = CartController();
      cart.tryAdd(_product(1, 10, '100.00'));

      final result = cart.tryAdd(_product(5, 20, '200.00'), shopName: 'Другой');

      expect(result, CartAddResult.requiresReset);
      expect(cart.shopId, 10);
      expect(cart.totalCount, 1);
      expect(cart.qtyOf(5), 0);
    });

    test('replaceWith очищает корзину и начинает заказ другого магазина', () {
      final cart = CartController();
      cart.tryAdd(_product(1, 10, '100.00'));
      cart.tryAdd(_product(2, 10, '50.00'));

      cart.replaceWith(_product(5, 20, '200.00'), shopName: 'Новый');

      expect(cart.shopId, 20);
      expect(cart.shopName, 'Новый');
      expect(cart.totalCount, 1);
      expect(cart.qtyOf(5), 1);
      expect(cart.subtotal, 200.00);
    });

    test('increment/decrement/remove и подсчёт сумм', () {
      final cart = CartController();
      cart.tryAdd(_product(1, 10, '100.00'));

      cart.increment(1);
      expect(cart.qtyOf(1), 2);
      expect(cart.subtotal, 200.00);

      cart.decrement(1);
      expect(cart.qtyOf(1), 1);

      // decrement до нуля удаляет позицию и сбрасывает магазин.
      cart.decrement(1);
      expect(cart.isEmpty, isTrue);
      expect(cart.shopId, isNull);

      cart.tryAdd(_product(1, 10, '100.00'));
      cart.remove(1);
      expect(cart.isEmpty, isTrue);
      expect(cart.subtotal, 0.0);
    });

    test('после очистки корзина принимает товар любого магазина', () {
      final cart = CartController();
      cart.tryAdd(_product(1, 10, '100.00'));
      cart.clear();

      expect(cart.tryAdd(_product(5, 20, '200.00')), CartAddResult.added);
      expect(cart.shopId, 20);
    });
  });
}
