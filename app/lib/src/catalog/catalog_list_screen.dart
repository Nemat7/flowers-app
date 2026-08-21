import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/product.dart';
import '../api/models/shop.dart';
import '../common/widgets/app_network_image.dart';
import '../home/widgets/shop_card.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';
import 'product_screen.dart';

/// Куда ведут «Все →» и круги категорий с главной: сетка товаров
/// (категория или «Наше фирменное») и полный список магазинов.
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({
    required this.title,
    this.categoryId,
    this.featured = false,
    super.key,
  });

  final String title;
  final int? categoryId;
  final bool featured;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  List<Product>? _products;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await context.read<ApiClient>().fetchProducts(
            categoryId: widget.categoryId,
            featured: widget.featured,
          );
      if (!mounted) return;
      setState(() => _products = page.results);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _CatalogBody(
        error: _error,
        onRetry: _load,
        isEmpty: _products?.isEmpty ?? false,
        emptyText: 'Здесь пока пусто',
        loaded: _products != null,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: _products?.length ?? 0,
          itemBuilder: (_, index) => _ProductTile(product: _products![index]),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductScreen(product: product),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AppNetworkImage(
                url: product.photo,
                height: double.infinity,
                placeholderSeed: product.id,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
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
    );
  }
}

/// Полный список магазинов — карточки те же, что на главной.
class ShopListScreen extends StatefulWidget {
  const ShopListScreen({super.key});

  @override
  State<ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<ShopListScreen> {
  List<Shop>? _shops;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await context.read<ApiClient>().fetchShops();
      if (!mounted) return;
      setState(() => _shops = page.results);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Магазины')),
      body: _CatalogBody(
        error: _error,
        onRetry: _load,
        isEmpty: _shops?.isEmpty ?? false,
        emptyText: 'Рядом пока нет магазинов',
        loaded: _shops != null,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: _shops?.length ?? 0,
          separatorBuilder: (_, _) => const SizedBox(height: 18),
          itemBuilder: (_, index) => ShopCard(shop: _shops![index]),
        ),
      ),
    );
  }
}

/// Общая обёртка загрузки/ошибки/пустого списка для обоих экранов.
class _CatalogBody extends StatelessWidget {
  const _CatalogBody({
    required this.error,
    required this.onRetry,
    required this.isEmpty,
    required this.emptyText,
    required this.loaded,
    required this.child,
  });

  final String? error;
  final VoidCallback onRetry;
  final bool isEmpty;
  final String emptyText;
  final bool loaded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(minimumSize: const Size(160, 44)),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (!loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (isEmpty) return Center(child: Text(emptyText));
    return child;
  }
}
