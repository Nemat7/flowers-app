import 'package:flowers_client/src/api/models/product.dart';
import 'package:flowers_client/src/api/models/shop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shop.fromJson — поля карточки главной', () {
    test('обложка, «наш магазин», профиль и тариф доставки', () {
      final shop = Shop.fromJson({
        'id': 1,
        'name': 'Bloom',
        'logo': 'http://h/media/logo.jpg',
        'cover_photo': 'http://h/media/cover.jpg',
        'is_own': true,
        'rating': '4.90',
        'rating_count': 12,
        'delivery_time_est': 35,
        'min_order': '50.00',
        'is_open': true,
        'kind': 'Цветы',
        'delivery_fee_from': 15.0,
      });

      expect(shop.coverPhoto, 'http://h/media/cover.jpg');
      expect(shop.coverImage, 'http://h/media/cover.jpg');
      expect(shop.isOwn, isTrue);
      expect(shop.kind, 'Цветы');
      expect(shop.deliveryFeeFrom, 15.0);
      expect(shop.deliveryTimeRange, '35–45 мин');
    });

    test('без обложки карточка падает на логотип', () {
      final shop = Shop.fromJson({
        'id': 2,
        'name': 'Guli Anor',
        'logo': 'http://h/media/logo.jpg',
        'cover_photo': '',
        'rating': '0.00',
        'min_order': '30.00',
        'is_open': false,
      });

      expect(shop.coverImage, 'http://h/media/logo.jpg');
      expect(shop.isOwn, isFalse);
      expect(shop.kind, isNull);
      expect(shop.deliveryFeeFrom, isNull);
      expect(shop.deliveryTimeRange, isNull);
    });
  });

  group('Product.fromJson', () {
    test('деталь: описание, все фото и название магазина', () {
      final product = Product.fromJson({
        'id': 7,
        'shop': 1,
        'category': 2,
        'name': 'Гортензия с орхидеей',
        'price': '450.00',
        'composition': 'гортензия, орхидея',
        'description': 'Голубая гортензия, белая орхидея фаленопсис.',
        'is_available': true,
        'is_featured': true,
        'photo': 'http://h/media/1.jpg',
        'photos': [
          {'id': 1, 'image': 'http://h/media/1.jpg', 'sort_order': 0},
          {'id': 2, 'image': 'http://h/media/2.jpg', 'sort_order': 1},
        ],
        'shop_detail': {'id': 1, 'name': 'Bloom', 'rating': 4.9},
      });

      expect(product.description, startsWith('Голубая гортензия'));
      expect(product.about, product.description);
      expect(product.isFeatured, isTrue);
      expect(product.photos, hasLength(2));
      expect(product.shopName, 'Bloom');
    });

    test('список: описания нет — под ценой показываем состав', () {
      final product = Product.fromJson({
        'id': 8,
        'shop': 1,
        'name': 'Букет тюльпанов',
        'price': '180.00',
        'composition': '21 тюльпан, крафт',
        'is_available': true,
      });

      expect(product.description, isEmpty);
      expect(product.about, '21 тюльпан, крафт');
      expect(product.isFeatured, isFalse);
      expect(product.photos, isEmpty);
      expect(product.shopName, isNull);
    });
  });

  group('PromoBanner.fromJson', () {
    test('баннер главной с тегом', () {
      final banner = PromoBanner.fromJson({
        'id': 1,
        'title': '−20% на первый заказ',
        'tag': 'Акция',
        'image': 'http://h/media/banner.jpg',
        'link_type': 'promo',
        'link_value': 'SPRING10',
      });

      expect(banner.title, '−20% на первый заказ');
      expect(banner.tag, 'Акция');
      expect(banner.linkType, 'promo');
      expect(banner.linkValue, 'SPRING10');
    });

    test('пустые поля не роняют парсинг', () {
      final banner = PromoBanner.fromJson({'id': 2, 'title': 'Доставка'});

      expect(banner.tag, isEmpty);
      expect(banner.image, isNull);
      expect(banner.linkValue, isEmpty);
    });
  });

  group('Category.fromJson', () {
    test('картинка круга на главной', () {
      final category = Category.fromJson({
        'id': 3,
        'name': 'Сладости',
        'slug': 'sladosti',
        'image': 'http://h/media/cat.jpg',
      });

      expect(category.slug, 'sladosti');
      expect(category.image, 'http://h/media/cat.jpg');
    });
  });
}
