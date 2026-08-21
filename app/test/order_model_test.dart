import 'package:flowers_client/src/api/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderSummary.fromJson', () {
    test('парсит заказ списка со строковым decimal', () {
      final order = OrderSummary.fromJson({
        'id': 42,
        'number': 'F-004521',
        'status': 'shop_pending',
        'shop': 12,
        'shop_name': 'Лотос',
        'slot_type': 'asap',
        'total': '535.00',
        'created_at': '2026-08-07T10:32:00Z',
      });
      expect(order.id, 42);
      expect(order.number, 'F-004521');
      expect(order.shopName, 'Лотос');
      expect(order.total, 535.0);
      expect(order.createdAt, isNotNull);
    });
  });

  group('OrderDetail.fromJson', () {
    test('парсит детали: позиции, суммы-строки, история, PIN, адрес', () {
      final order = OrderDetail.fromJson({
        'id': 42,
        'number': 'F-004521',
        'status': 'delivered',
        'shop': 12,
        'shop_name': 'Лотос',
        'slot_type': 'scheduled',
        'scheduled_at': '2026-08-08T09:00:00Z',
        'total': '535.00',
        'subtotal': '450.00',
        'delivery_fee': '85.00',
        'discount': '0.00',
        'card_text': 'С днём рождения!',
        'is_anonymous': false,
        'recipient_name': 'Мадина',
        'recipient_phone': '+992901234567',
        'comment': '',
        'cancel_reason': null,
        'delivery_pin': '4821',
        'address': {
          'lat': 38.5598,
          'lng': 68.7870,
          'address_text': 'ул. Рудаки 25',
          'details': 'подъезд 2',
        },
        'items': [
          {
            'id': 1,
            'product': 101,
            'product_name': '25 роз «Фридом»',
            'price': '450.00',
            'qty': 1,
            'photo_url': '/media/products/101.jpg',
          },
          {
            'id': 2,
            'product': 205,
            'product_name': 'Raffaello, 150 г',
            'price': '42.50',
            'qty': 2,
            'photo_url': null,
          },
        ],
        'status_history': [
          {'status': 'created', 'comment': '', 'created_at': '2026-08-07T10:30:00Z'},
          {'status': 'paid', 'comment': null, 'created_at': '2026-08-07T10:31:00Z'},
        ],
        'created_at': '2026-08-07T10:30:00Z',
      });

      expect(order.items, hasLength(2));
      expect(order.items[0].productName, '25 роз «Фридом»');
      expect(order.items[0].price, 450.0);
      expect(order.items[1].lineTotal, closeTo(85.0, 0.001));
      expect(order.subtotal, 450.0);
      expect(order.deliveryFee, 85.0);
      expect(order.discount, 0.0);
      expect(order.deliveryPin, '4821');
      expect(order.address!.addressText, 'ул. Рудаки 25');
      expect(order.address!.lat, closeTo(38.5598, 0.0001));
      expect(order.statusHistory, hasLength(2));
      expect(order.statusHistory[1].status, 'paid');
      expect(order.scheduledAt, isNotNull);
    });

    test('опциональные поля отсутствуют — безопасные дефолты', () {
      final order = OrderDetail.fromJson({
        'id': 1,
        'number': 'F-000001',
        'status': 'created',
        'shop': 12,
        'total': '100.00',
      });
      expect(order.items, isEmpty);
      expect(order.statusHistory, isEmpty);
      expect(order.deliveryPin, isNull);
      expect(order.address, isNull);
      expect(order.bouquetPhoto, isNull);
      expect(order.subtotal, 0.0);
    });

    test('bouquet_photo: парсинг ожидания и решения клиента', () {
      Map<String, dynamic> base(Object? photo) => {
            'id': 1,
            'number': 'F-000001',
            'status': 'preparing',
            'shop': 12,
            'total': '100.00',
            'bouquet_photo': photo,
          };

      final pending = OrderDetail.fromJson(base({
        'url': 'http://localhost:8002/media/order_photos/9.jpg',
        'approved': null,
      }));
      expect(pending.bouquetPhoto, isNotNull);
      expect(pending.bouquetPhoto!.url, endsWith('/media/order_photos/9.jpg'));
      expect(pending.bouquetPhoto!.awaitingResponse, isTrue);

      final approved = OrderDetail.fromJson(base({
        'url': 'http://localhost:8002/media/order_photos/9.jpg',
        'approved': true,
      }));
      expect(approved.bouquetPhoto!.awaitingResponse, isFalse);
      expect(approved.bouquetPhoto!.approved, isTrue);

      expect(OrderDetail.fromJson(base(null)).bouquetPhoto, isNull);
    });
  });

  group('CreatedOrder / PaymentResult', () {
    test('CreatedOrder парсит total-строку', () {
      final created = CreatedOrder.fromJson({
        'id': 7,
        'number': 'F-000007',
        'status': 'created',
        'total': '535.00',
        'payment': null,
      });
      expect(created.total, 535.0);
      expect(created.status, 'created');
    });

    test('PaymentResult.isSuccess только при status success', () {
      final success = PaymentResult.fromJson({
        'payment_id': 3,
        'provider': 'stub',
        'amount': '535.00',
        'status': 'success',
      });
      expect(success.isSuccess, isTrue);
      expect(success.amount, 535.0);

      final pending = PaymentResult.fromJson({
        'payment_id': 3,
        'provider': 'stub',
        'amount': '535.00',
        'status': 'pending',
      });
      expect(pending.isSuccess, isFalse);
    });
  });

  group('orderStatusLabel', () {
    test('русские метки для известных статусов и fallback', () {
      expect(orderStatusLabel('shop_pending'), 'Ждёт магазин');
      expect(orderStatusLabel('on_the_way'), 'В пути');
      expect(orderStatusLabel('delivered'), 'Доставлен');
      expect(orderStatusLabel('unknown_status'), 'unknown_status');
    });
  });
}
