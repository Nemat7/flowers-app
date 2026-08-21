import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/product.dart';
import '../cart/cart_actions.dart';
import '../cart/cart_controller.dart';
import '../common/widgets/app_network_image.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';
import '../theme/theme.dart';

/// Категории-сладости для кросс-сейла «Добавьте сладости к букету».
/// Эвристика по названию категории (slug у API нет).
bool isSweetsCategoryName(String name) {
  final lower = name.toLowerCase();
  return const [
    'сладост',
    'десерт',
    'торт',
    'конфет',
    'шоколад',
    'печень',
    'макарон',
    'снек',
  ].any(lower.contains);
}

/// Карточка товара (макет v5 03-product): фото full-bleed 55% экрана,
/// белый шит radius 24 наезжает на фото на 28px, внизу закреплённая панель —
/// серый степпер 118×50 + чёрная пилюля «В корзину · X с.».
///
/// [shopName] и [crossSell] передаёт витрина магазина, у которой они уже есть;
/// при открытии с главной оба подгружаются сами. Описание и полный список фото
/// всегда добираются из `GET /products/{id}/` — в списках их нет.
class ProductScreen extends StatefulWidget {
  const ProductScreen({
    required this.product,
    this.shopName,
    this.crossSell,
    super.key,
  });

  final Product product;
  final String? shopName;

  /// Товары того же магазина из категорий сладостей (без текущего).
  final List<Product>? crossSell;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  int _qty = 1;
  late Product _product = widget.product;
  late String? _shopName = widget.shopName;
  late List<Product> _crossSell = widget.crossSell ?? const [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  /// Деталь товара (описание, все фото, магазин) и — при открытии с главной —
  /// кросс-сейл. Ошибка не критична: экран уже показывает данные из списка.
  Future<void> _loadDetails() async {
    final api = context.read<ApiClient>();
    try {
      final detail = await api.fetchProduct(widget.product.id);
      if (!mounted) return;
      setState(() {
        _product = detail;
        _shopName ??= detail.shopName;
      });
    } on ApiException {
      // остаёмся на данных из списка
    }
    if (widget.crossSell != null) return;
    try {
      final (products, categories) = await (
        api.fetchProducts(shopId: widget.product.shopId),
        api.fetchCategories(),
      ).wait;
      if (!mounted) return;
      final sweetsIds = categories
          .where((c) => isSweetsCategoryName(c.name))
          .map((c) => c.id)
          .toSet();
      setState(() {
        _crossSell = products.results
            .where((p) =>
                p.id != widget.product.id &&
                p.isAvailable &&
                sweetsIds.contains(p.categoryId))
            .toList();
      });
    } on ApiException {
      // кросс-сейл необязателен
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _product.price * _qty;
    // .photo { height:464px } при высоте макета 844.
    final photoHeight = MediaQuery.of(context).size.height * 0.55;
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: _buildCta(total),
      body: SingleChildScrollView(
        child: Stack(
          children: [
            _buildHero(photoHeight),
            // .sheet { margin-top:-28px } — шит поверх фото, поэтому он второй
            // в Stack: в CustomScrollView фото красилось сверху и срезало заголовок.
            Padding(
              padding: EdgeInsets.only(top: photoHeight - 28),
              child: _buildSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheet() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _product.name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatSomoni(_product.price),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (_product.about.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _product.about,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (_crossSell.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Добавить к заказу',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            _buildCrossSell(),
          ],
        ],
      ),
    );
  }

  Widget _buildHero(double height) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppNetworkImage(
            url: _product.photo,
            height: height,
            placeholderSeed: _product.id,
            placeholderIcon: Icons.local_florist,
          ),
          // .photo::after — затемнение сверху под круглые кнопки.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, -0.35),
                colors: [Color(0x4D000000), Colors.transparent],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: _RoundButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: const _RoundButton(icon: Icons.favorite_border_rounded),
          ),
        ],
      ),
    );
  }

  /// .xcard { flex:0 0 158px } — фото 68, название, цена и круглый «+».
  Widget _buildCrossSell() {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _crossSell.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, index) {
          final item = _crossSell[index];
          return SizedBox(
            width: 158,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: AppNetworkImage(
                      url: item.photo,
                      height: 68,
                      placeholderSeed: item.id,
                      placeholderIcon: Icons.cake_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatSomoni(item.price),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => addToCartWithConfirm(
                    context,
                    item,
                    shopName: _shopName ?? '',
                  ),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.add, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// .bottombar — серый степпер-пилюля + чёрная CTA-пилюля.
  Widget _buildCta(double total) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      child: Row(
        children: [
          Container(
            width: 118,
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _qtyButton(
                  icon: Icons.remove,
                  onTap: _qty > 1 ? () => setState(() => _qty--) : null,
                ),
                Text(
                  '$_qty',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _qtyButton(
                  icon: Icons.add,
                  onTap: () => setState(() => _qty++),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _addToCart,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text('В корзину · ${formatSomoni(total)}'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCart() async {
    // Первая единица — через helper: он же покажет диалог «один магазин».
    // Остальные — напрямую, если первая прошла без конфликта/после замены.
    final cart = context.read<CartController>();
    final before = cart.qtyOf(_product.id);
    await addToCartWithConfirm(context, _product, shopName: _shopName ?? '');
    if (!mounted) return;
    final after = cart.qtyOf(_product.id);
    if (after == before) return; // пользователь отменил замену корзины
    for (var i = 0; i < _qty - 1; i++) {
      cart.tryAdd(_product, shopName: _shopName ?? '');
    }
  }

  Widget _qtyButton({required IconData icon, VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? AppColors.textHint : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Круглая белая кнопка поверх фото с тенью (макет 03-product .rbtn).
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: kFloatingShadow,
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}
