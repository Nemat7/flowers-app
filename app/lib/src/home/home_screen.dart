import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/product.dart';
import '../api/models/shop.dart';
import '../auth/auth_controller.dart';
import '../catalog/catalog_list_screen.dart';
import '../common/widgets/app_network_image.dart';
import '../shell/main_shell.dart';
import '../theme/colors.dart';
import 'widgets/banner_carousel.dart';
import 'widgets/featured_card.dart';
import 'widgets/shop_card.dart';

/// Главная (макет v5 01-home): пилюля адреса и колокольчик, приветствие,
/// поиск, карусель баннеров с точками, круги категорий, лента «Наше
/// фирменное», список магазинов рядом. Скроллится целиком — шапка уезжает
/// вверх вместе с контентом, как в макете.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Shop>? _shops;
  List<Category> _categories = [];
  List<Product> _featured = [];
  List<PromoBanner> _banners = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final api = context.read<ApiClient>();
    // Магазины — обязательны, остальные блоки необязательны: если баннеров
    // или фирменных товаров нет, секция просто не рисуется.
    try {
      final page = await api.fetchShops();
      if (!mounted) return;
      setState(() => _shops = page.results);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      return;
    }
    final results = await Future.wait([
      api.fetchBanners().catchError((_) => <PromoBanner>[]),
      api.fetchCategories().catchError((_) => <Category>[]),
      api
          .fetchProducts(featured: true)
          .then((page) => page.results)
          .catchError((_) => <Product>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _banners = results[0] as List<PromoBanner>;
      _categories = results[1] as List<Category>;
      _featured = results[2] as List<Product>;
    });
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Header()),
              const SliverToBoxAdapter(child: _Greeting()),
              const SliverToBoxAdapter(child: _SearchRow()),
              if (_banners.isNotEmpty)
                SliverToBoxAdapter(child: BannerCarousel(banners: _banners)),
              if (_categories.isNotEmpty) ...[
                const SliverToBoxAdapter(child: _SectionHead('Категории')),
                SliverToBoxAdapter(child: _buildCategories()),
              ],
              if (_featured.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SectionHead(
                    'Наше фирменное',
                    onSeeAll: () => _open(
                      const ProductListScreen(
                        title: 'Наше фирменное',
                        featured: true,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _buildFeatured()),
              ],
              SliverToBoxAdapter(
                child: _SectionHead(
                  'Магазины рядом',
                  onSeeAll: (_shops?.isEmpty ?? true)
                      ? null
                      : () => _open(const ShopListScreen()),
                ),
              ),
              ..._buildShops(),
            ],
          ),
        ),
      ),
    );
  }

  /// .cats — четыре круга 70px с подписями, ровно по ширине экрана.
  Widget _buildCategories() {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemExtent: (MediaQuery.of(context).size.width - 32) / 4,
        itemCount: _categories.length,
        itemBuilder: (_, index) {
          final category = _categories[index];
          return _CategoryCircle(
            category: category,
            onTap: () => _open(
              ProductListScreen(
                title: category.name,
                categoryId: category.id,
              ),
            ),
          );
        },
      ),
    );
  }

  /// .feat — карточки 150px с бейджем «Наш бренд».
  Widget _buildFeatured() {
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 16, right: 4),
        itemCount: _featured.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, index) => FeaturedCard(product: _featured[index]),
      ),
    );
  }

  List<Widget> _buildShops() {
    const bottomPadding = EdgeInsets.only(bottom: kFloatingTabBarClearance);
    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
            child: Column(
              children: [
                const Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
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
      ];
    }
    final shops = _shops;
    if (shops == null) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          ),
        ),
      ];
    }
    if (shops.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 48),
            child: Column(
              children: [
                Icon(Icons.storefront, size: 48, color: AppColors.textHint),
                SizedBox(height: 12),
                Text('Рядом пока нет магазинов'),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16).add(bottomPadding),
        sliver: SliverList.separated(
          itemCount: shops.length,
          separatorBuilder: (_, _) => const SizedBox(height: 18),
          itemBuilder: (_, index) => ShopCard(shop: shops[index]),
        ),
      ),
    ];
  }
}

/// .topbar — пилюля адреса + круглый колокольчик.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              decoration: BoxDecoration(
                color: AppColors.fill,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Доставка',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          'ул. Рудаки 25',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: AppColors.fill,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_outlined,
              size: 21,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// .greet — «Что подарим, {имя}?» в две строки, как в макете.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final name = user?.name;
    final hasName = name != null && name.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Text(
        hasName ? 'Что подарим,\n$name?' : 'Что подарим?',
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          height: 1.15,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// .searchrow — строка поиска (пока заглушка) + круглая кнопка фильтров.
class _SearchRow extends StatelessWidget {
  const _SearchRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.fill,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded,
                      size: 18, color: AppColors.textSecondary),
                  SizedBox(width: 10),
                  Text(
                    'Найти букет или магазин…',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.fill,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.tune_rounded,
              size: 20,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// .sechead — заголовок секции и ссылка «Все →».
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.title, {this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'Все →',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// .cat — круг 70px с картинкой категории и подписью.
class _CategoryCircle extends StatelessWidget {
  const _CategoryCircle({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: 70,
              height: 70,
              child: AppNetworkImage(
                url: category.image,
                height: 70,
                placeholderSeed: category.id,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
