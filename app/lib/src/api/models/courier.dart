/// Модели курьерского API (api.md §6).
/// Decimal-поля приходят строками («10.00») — парсим в double.

/// Магазин в карточке заказа курьера.
class CourierOrderShop {
  const CourierOrderShop({
    required this.id,
    required this.name,
    required this.addressText,
    this.lat,
    this.lng,
  });

  factory CourierOrderShop.fromJson(Map<String, dynamic> json) =>
      CourierOrderShop(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        addressText: json['address_text'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  final int id;
  final String name;
  final String addressText;
  final double? lat;
  final double? lng;
}

/// Адрес доставки в карточке заказа курьера.
class CourierOrderAddress {
  const CourierOrderAddress({
    required this.addressText,
    this.lat,
    this.lng,
    this.details,
  });

  factory CourierOrderAddress.fromJson(Map<String, dynamic> json) =>
      CourierOrderAddress(
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        addressText: json['address_text'] as String? ?? '',
        details: json['details'] as String?,
      );

  final double? lat;
  final double? lng;
  final String addressText;
  final String? details;
}

/// Карточка заказа для курьера — доступные, текущий и история доставок
/// (`CourierOrderSerializer`; в истории добавляется `delivered_at`).
class CourierOrder {
  const CourierOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.shop,
    required this.address,
    required this.recipientName,
    required this.recipientPhone,
    required this.total,
    required this.deliveryFee,
    this.fee,
    this.distance,
    this.createdAt,
    this.deliveredAt,
  });

  factory CourierOrder.fromJson(Map<String, dynamic> json) => CourierOrder(
        id: json['id'] as int,
        number: json['number'] as String,
        status: json['status'] as String,
        shop: json['shop'] is Map<String, dynamic>
            ? CourierOrderShop.fromJson(json['shop'] as Map<String, dynamic>)
            : const CourierOrderShop(id: 0, name: '', addressText: ''),
        address: json['address'] is Map<String, dynamic>
            ? CourierOrderAddress.fromJson(
                json['address'] as Map<String, dynamic>,
              )
            : const CourierOrderAddress(addressText: ''),
        recipientName: json['recipient_name'] as String? ?? '',
        recipientPhone: json['recipient_phone'] as String? ?? '',
        total: double.tryParse('${json['total']}') ?? 0,
        deliveryFee: double.tryParse('${json['delivery_fee']}') ?? 0,
        fee: double.tryParse('${json['fee']}'),
        distance: (json['distance'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse('${json['created_at']}'),
        deliveredAt: DateTime.tryParse('${json['delivered_at']}'),
      );

  final int id;
  final String number;
  final String status;
  final CourierOrderShop shop;
  final CourierOrderAddress address;
  final String recipientName;
  final String recipientPhone;
  final double total;
  final double deliveryFee;

  /// Заработок курьера за заказ (`null` — доставка ещё не назначена).
  final double? fee;

  /// Дистанция от текущей позиции курьера до магазина, метры
  /// (`null` — позиция курьера неизвестна).
  final double? distance;
  final DateTime? createdAt;
  final DateTime? deliveredAt;

  /// Копия с другим статусом — для шагов active-заказа.
  CourierOrder copyWithStatus(String status) => CourierOrder(
        id: id,
        number: number,
        status: status,
        shop: shop,
        address: address,
        recipientName: recipientName,
        recipientPhone: recipientPhone,
        total: total,
        deliveryFee: deliveryFee,
        fee: fee,
        distance: distance,
        createdAt: createdAt,
        deliveredAt: deliveredAt,
      );
}

/// Ответ action-эндпоинтов курьера (accept/pickup/arrive/complete): `{id, status}`.
class CourierOrderAction {
  const CourierOrderAction({required this.id, required this.status});

  factory CourierOrderAction.fromJson(Map<String, dynamic> json) =>
      CourierOrderAction(
        id: json['id'] as int,
        status: json['status'] as String,
      );

  final int id;
  final String status;
}

/// `GET /courier/earnings/` — заработок: сегодня / неделя / всего.
class CourierEarnings {
  const CourierEarnings({
    required this.today,
    required this.week,
    required this.total,
  });

  factory CourierEarnings.fromJson(Map<String, dynamic> json) =>
      CourierEarnings(
        today: double.tryParse('${json['today']}') ?? 0,
        week: double.tryParse('${json['week']}') ?? 0,
        total: double.tryParse('${json['total']}') ?? 0,
      );

  final double today;
  final double week;
  final double total;
}

/// Точка GPS-трека для `POST /courier/location/` (`ts` — unixtime, секунды).
class CourierLocationPoint {
  const CourierLocationPoint({
    required this.lat,
    required this.lng,
    required this.ts,
  });

  final double lat;
  final double lng;
  final double ts;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'ts': ts};
}
