import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/product.dart';
import '../api/models/shop.dart';
import '../cart/cart_actions.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_screen.dart';
import '../catalog/product_screen.dart';
import '../common/widgets/app_network_image.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';

/// Витрина магазина (макет 02-shop): герой-обложка, карточка магазина,
/// чипы категорий, сетка товаров 2 в ряд.
class ShopScreen extends StatefulWidget {
  const ShopScreen({required this.shopId, super.key});

  final int shopId;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  Shop? _shop;
  List<Product> _products = [];
  List<Category> _categories = [];
  String? _error;
  int? _selectedCategoryId; // null = «Все»

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final api = context.read<ApiClient>();
    try {
      final (shop, products, categories) = await (
        api.fetchShop(widget.shopId),
        api.fetchProducts(shopId: widget.shopId),
        api.fetchCategories(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _products = products.results;
        _categories = categories;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  List<Product> get _visibleProducts => _selectedCategoryId == null
      ? _products
      : _products
          .where((p) => p.categoryId == _selectedCategoryId)
          .toList();

  /// Категории, реально присутствующие в товарах магазина.
  List<Category> get _shopCategories {
    final ids = _products.map((p) => p.categoryId).toSet();
    return _categories.where((c) => ids.contains(c.id)).toList();
  }

  /// Кросс-сейл для карточки товара: сладости того же магазина
  /// (категория определяется эвристикой по названию).
  List<Product> _crossSellFor(Product product) {
    final sweetsCategoryIds = _categories
        .where((c) => isSweetsCategoryName(c.name))
        .map((c) => c.id)
        .toSet();
    return _products
        .where((p) =>
            p.id != product.id &&
            p.isAvailable &&
            sweetsCategoryIds.contains(p.categoryId))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final shop = _shop;
    final cart = context.watch<CartController>();
    final showPill = shop != null && cart.shopId == shop.id && !cart.isEmpty;
    return Scaffold(
      body: _error != null
          ? _buildError()
          : shop == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                )
              : Stack(
                  children: [
                    RefreshIndicator(
                      color: AppColors.accent,
                      onRefresh: _load,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _Hero(shop: shop)),
                          SliverToBoxAdapter(child: _ShopInfo(shop: shop)),
                          if (_shopCategories.length > 1)
                            SliverToBoxAdapter(child: _buildCategoryChips()),
                          _buildGrid(),
                        ],
                      ),
                    ),
                    if (showPill) const CartPill(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off,
                      size: 48, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _load,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(160, 44),
                    ),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    final chips = <(int?, String)>[
      (null, 'Все'),
      ..._shopCategories.map((c) => (c.id as int?, c.name)),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final (id, label) = chips[index];
          final selected = id == _selectedCategoryId;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategoryId = id),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: selected ? AppColors.textPrimary : AppColors.fill,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid() {
    final products = _visibleProducts;
    if (products.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('В этом магазине пока нет товаров'),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 14,
          childAspectRatio: 0.95,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, index) {
            final product = products[index];
            final shop = _shop!;
            return _ProductCard(
              product: product,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProductScreen(
                    product: product,
                    shopName: shop.name,
                    crossSell: _crossSellFor(product),
                  ),
                ),
              ),
              onAdd: () => addToCartWithConfirm(
                context,
                product,
                shopName: shop.name,
              ),
            );
          },
          childCount: products.length,
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppNetworkImage(
            // обложка витрины; логотип — только если обложки нет
            url: shop.coverImage,
            height: 210,
            placeholderSeed: shop.id,
          ),
          // Затемнение сверху под кнопку назад.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0x52000000), Colors.transparent],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: _NavButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          // Корзина с бейджем количества.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: _CartButton(shopId: shop.id),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xEBFFFFFF),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Кнопка корзины на герое витрины с бейджем количества позиций.
class _CartButton extends StatelessWidget {
  const _CartButton({required this.shopId});

  final int shopId;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    // Бейдж показываем только для корзины ЭТОГО магазина.
    final count = cart.shopId == shopId ? cart.totalCount : 0;
    return Material(
      color: const Color(0xEBFFFFFF),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CartScreen()),
        ),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.shopping_bag_outlined,
                size: 18,
                color: AppColors.textPrimary,
              ),
              if (count > 0)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 15),
                    height: 15,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopInfo extends StatelessWidget {
  const _ShopInfo({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shop.name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _metaLine(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _StatusBadge(shop: shop),
        ],
      ),
    );
  }

  /// «★ 4.9 (200+) · 35 мин · мин. заказ 150 с. · ул. Рудаки 25».
  String _metaLine() {
    return <String>[
      if (shop.ratingCount > 0)
        '★ ${formatRating(shop.rating)} (${shop.ratingCount})'
      else
        'Новый магазин',
      if (shop.deliveryTimeEst != null) '${shop.deliveryTimeEst} мин',
      'мин. заказ ${formatSomoni(shop.minOrder)}',
      if (shop.addressText != null) shop.addressText!,
    ].join(' · ');
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final openLabel = shop.openUntilLabel;
    final isOpen = shop.isOpen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isOpen ? AppColors.successSurface : AppColors.fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isOpen ? (openLabel ?? 'Открыто') : 'Закрыто',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: isOpen ? AppColors.accent : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.onAdd,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AppNetworkImage(
                    url: product.photo,
                    height: double.infinity,
                    placeholderSeed: product.id,
                    placeholderIcon: product.categoryId == 3
                        ? Icons.cake_outlined
                        : Icons.local_florist,
                  ),
                ),
                // Чёрный круглый «+» поверх фото (макет 02-shop).
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: AppColors.textPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add,
                          size: 17, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 7, 2, 0),
            child: Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
            child: Text(
              formatSomoni(product.price),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
