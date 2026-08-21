import 'package:flowers_client/src/api/models/courier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CourierOrder.fromJson', () {
    test('карточка из GET /courier/orders/available/ (фактический ответ)', () {
      final order = CourierOrder.fromJson(const {
        'id': 1,
        'number': 'F-300064',
        'status': 'ready',
        'shop': {
          'id': 1,
          'name': 'Флора Душанбе',
          'address_text': 'пр. Рудаки 25',
          'lat': 38.5598,
          'lng': 68.787,
        },
        'address': {
          'lat': 38.565,
          'lng': 68.79,
          'address_text': 'ул. Рудаки 25',
          'details': 'подъезд 2',
        },
        'recipient_name': 'Гульчехра',
        'recipient_phone': '+992900000009',
        'total': '492.77',
        'delivery_fee': '11.27',
        'fee': '0.00',
        'distance': 187,
        'created_at': '2026-08-06T16:31:58.946746+05:00',
      });

      expect(order.id, 1);
      expect(order.number, 'F-300064');
      expect(order.status, 'ready');
      expect(order.shop.name, 'Флора Душанбе');
      expect(order.shop.lat, closeTo(38.5598, 1e-9));
      expect(order.address.addressText, 'ул. Рудаки 25');
      expect(order.address.details, 'подъезд 2');
      expect(order.recipientPhone, '+992900000009');
      expect(order.total, closeTo(492.77, 1e-9));
      expect(order.deliveryFee, closeTo(11.27, 1e-9));
      expect(order.fee, closeTo(0, 1e-9));
      expect(order.distance, closeTo(187, 1e-9));
      expect(order.createdAt, isNotNull);
      expect(order.deliveredAt, isNull);
    });

    test('запись истории: delivered_at парсится, distance/fee могут быть null',
        () {
      final order = CourierOrder.fromJson(const {
        'id': 9,
        'number': 'F-975264',
        'status': 'delivered',
        'shop': {
          'id': 1,
          'name': 'Флора Душанбе',
          'address_text': 'пр. Рудаки 25',
          'lat': 38.5598,
          'lng': 68.787,
        },
        'address': {
          'lat': 38.5598,
          'lng': 68.787,
          'address_text': 'Рудаки 25',
          'details': '',
        },
        'recipient_name': 'Гульчехра',
        'recipient_phone': '+992900000009',
        'total': '360.00',
        'delivery_fee': '10.00',
        'fee': '10.00',
        'distance': null,
        'created_at': '2026-08-07T21:06:41.144280+05:00',
        'delivered_at': '2026-08-07T16:06:42.282026Z',
      });

      expect(order.distance, isNull);
      expect(order.fee, closeTo(10, 1e-9));
      expect(order.deliveredAt, isNotNull);
      expect(order.deliveredAt!.isUtc, isTrue);
    });

    test('fee null (заказ без назначенной доставки) не роняет парсинг', () {
      final order = CourierOrder.fromJson(const {
        'id': 2,
        'number': 'F-1',
        'status': 'ready',
        'shop': {'id': 1, 'name': 'М', 'address_text': 'А'},
        'address': {'address_text': 'Б'},
        'recipient_name': '',
        'recipient_phone': '',
        'total': '10.00',
        'delivery_fee': '5.00',
        'fee': null,
        'distance': null,
        'created_at': null,
      });

      expect(order.fee, isNull);
      expect(order.createdAt, isNull);
      expect(order.shop.lat, isNull);
    });

    test('copyWithStatus сохраняет остальные поля', () {
      final order = CourierOrder.fromJson(const {
        'id': 3,
        'number': 'F-2',
        'status': 'courier_assigned',
        'shop': {'id': 1, 'name': 'М', 'address_text': 'А'},
        'address': {'address_text': 'Б'},
        'recipient_name': 'Г',
        'recipient_phone': '+992',
        'total': '10.00',
        'delivery_fee': '5.00',
        'fee': '5.00',
        'distance': 100,
        'created_at': null,
      });
      final copy = order.copyWithStatus('on_the_way');

      expect(copy.status, 'on_the_way');
      expect(copy.id, order.id);
      expect(copy.fee, order.fee);
      expect(copy.address.addressText, 'Б');
    });
  });

  test('CourierEarnings.fromJson: decimal-строки в double', () {
    final earnings = CourierEarnings.fromJson(
      const {'today': '0.00', 'week': '25.50', 'total': '60.00'},
    );
    expect(earnings.today, 0);
    expect(earnings.week, closeTo(25.5, 1e-9));
    expect(earnings.total, closeTo(60, 1e-9));
  });

  test('CourierOrderAction.fromJson: {id, status}', () {
    final action = CourierOrderAction.fromJson(
      const {'id': 10, 'status': 'on_the_way'},
    );
    expect(action.id, 10);
    expect(action.status, 'on_the_way');
  });

  test('CourierLocationPoint.toJson: {lat, lng, ts}', () {
    final point = CourierLocationPoint(lat: 38.56, lng: 68.78, ts: 1754800000);
    expect(point.toJson(), {
      'lat': closeTo(38.56, 1e-9),
      'lng': closeTo(68.78, 1e-9),
      'ts': closeTo(1754800000, 1e-9),
    });
  });
}
