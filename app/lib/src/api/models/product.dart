/// Товар из `GET /products/`. Цена — decimal-строка («350.00»).
class Product {
  const Product({
    required this.id,
    required this.shopId,
    required this.name,
    required this.price,
    required this.isAvailable,
    this.categoryId,
    this.composition = '',
    this.description = '',
    this.isFeatured = false,
    this.tags = const [],
    this.photo,
    this.photos = const [],
    this.shopName,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as int,
        shopId: json['shop'] as int,
        categoryId: json['category'] as int?,
        name: json['name'] as String,
        price: double.tryParse('${json['price']}') ?? 0,
        composition: json['composition'] as String? ?? '',
        // description и photos приходят только из GET /products/{id}/
        description: json['description'] as String? ?? '',
        isFeatured: json['is_featured'] as bool? ?? false,
        tags: (json['tags'] as List<dynamic>? ?? [])
            .map((tag) => '$tag')
            .toList(),
        isAvailable: json['is_available'] as bool? ?? true,
        photo: json['photo'] as String?,
        photos: (json['photos'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((photo) => '${photo['image']}')
            .toList(),
        shopName: (json['shop_detail'] as Map<String, dynamic>?)?['name']
            as String?,
      );

  final int id;
  final int shopId;
  final int? categoryId;
  final String name;
  final double price;
  final String composition;

  /// Развёрнутое описание с карточки товара; пусто в списках.
  final String description;

  /// Лента «Наше фирменное» + бейдж «Наш бренд» на главной.
  final bool isFeatured;
  final List<String> tags;
  final bool isAvailable;
  final String? photo;

  /// Все фото товара (из детали); первое совпадает с [photo].
  final List<String> photos;

  /// Название магазина — приходит только в детали (`shop_detail`).
  final String? shopName;

  /// Текст под ценой на карточке товара: описание, иначе состав.
  String get about => description.isNotEmpty ? description : composition;
}

/// Категория каталога из `GET /categories/` (ответ — простой список).
class Category {
  const Category({
    required this.id,
    required this.name,
    this.slug = '',
    this.image,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        name: json['name'] as String,
        slug: json['slug'] as String? ?? '',
        image: json['image'] as String?,
      );

  final int id;
  final String name;
  final String slug;

  /// Круглая картинка категории на главной.
  final String? image;
}

/// Баннер главного экрана из `GET /banners/` (ответ — простой список).
/// Не `Banner` — это имя занято одноимённым виджетом material.
class PromoBanner {
  const PromoBanner({
    required this.id,
    required this.title,
    this.tag = '',
    this.image,
    this.linkType = '',
    this.linkValue = '',
  });

  factory PromoBanner.fromJson(Map<String, dynamic> json) => PromoBanner(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        image: json['image'] as String?,
        linkType: json['link_type'] as String? ?? '',
        linkValue: json['link_value'] as String? ?? '',
      );

  final int id;
  final String title;

  /// Подпись над заголовком: «Акция», «Доставка».
  final String tag;
  final String? image;
  final String linkType;
  final String linkValue;
}
