import 'package:flutter/foundation.dart';

import '../api/models/product.dart';

/// Позиция корзины: товар + количество.
class CartItem {
  const CartItem({required this.product, required this.qty});

  final Product product;
  final int qty;

  double get lineTotal => product.price * qty;

  CartItem copyWith({int? qty}) => CartItem(product: product, qty: qty ?? this.qty);
}

/// Результат попытки добавить товар в корзину.
enum CartAddResult {
  /// Товар добавлен (количество увеличено).
  added,

  /// Товар из ДРУГОГО магазина: корзина не тронута,
  /// UI должен спросить подтверждение на очистку.
  requiresReset,
}

/// Локальное состояние корзины. Бизнес-правило: один заказ = один магазин,
/// поэтому корзина привязана к [shopId]; товар другого магазина добавляется
/// только через [replaceWith] (после подтверждения пользователя).
class CartController extends ChangeNotifier {
  final Map<int, CartItem> _items = {}; // productId → позиция
  int? _shopId;
  String? _shopName;

  int? get shopId => _shopId;
  String? get shopName => _shopName;

  List<CartItem> get items => List.unmodifiable(_items.values);

  bool get isEmpty => _items.isEmpty;

  /// Суммарное количество единиц товара (для бейджа).
  int get totalCount => _items.values.fold(0, (sum, item) => sum + item.qty);

  /// Сумма товаров без доставки (точный итог знает только сервер).
  double get subtotal => _items.values.fold(0.0, (sum, item) => sum + item.lineTotal);

  int qtyOf(int productId) => _items[productId]?.qty ?? 0;

  /// Добавить единицу товара. Возвращает [CartAddResult.requiresReset],
  /// если товар из другого магазина — состояние при этом не меняется.
  CartAddResult tryAdd(Product product, {String? shopName}) {
    if (_shopId != null && _shopId != product.shopId) {
      return CartAddResult.requiresReset;
    }
    _shopId = product.shopId;
    _shopName = shopName ?? _shopName;
    final existing = _items[product.id];
    _items[product.id] = existing == null
        ? CartItem(product: product, qty: 1)
        : existing.copyWith(qty: existing.qty + 1);
    notifyListeners();
    return CartAddResult.added;
  }

  /// Очистить корзину и начать заказ из другого магазина
  /// (пользователь подтвердил диалог «Очистить корзину?»).
  void replaceWith(Product product, {String? shopName}) {
    _items.clear();
    _shopId = null;
    _shopName = null;
    tryAdd(product, shopName: shopName);
  }

  void increment(int productId) {
    final existing = _items[productId];
    if (existing == null) return;
    _items[productId] = existing.copyWith(qty: existing.qty + 1);
    notifyListeners();
  }

  /// Уменьшить количество; при 0 позиция удаляется.
  void decrement(int productId) {
    final existing = _items[productId];
    if (existing == null) return;
    if (existing.qty <= 1) {
      remove(productId);
      return;
    }
    _items[productId] = existing.copyWith(qty: existing.qty - 1);
    notifyListeners();
  }

  void remove(int productId) {
    _items.remove(productId);
    if (_items.isEmpty) {
      _shopId = null;
      _shopName = null;
    }
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _shopId = null;
    _shopName = null;
    notifyListeners();
  }
}
