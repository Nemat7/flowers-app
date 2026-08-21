/// Заказ клиента из `GET /orders/` (список) и `GET /orders/{id}/` (детали).
/// Decimal-поля API приходят строками («350.00») — парсим в double.
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.shopId,
    required this.shopName,
    required this.slotType,
    required this.total,
    this.shopLogo,
    this.createdAt,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
        id: json['id'] as int,
        number: json['number'] as String,
        status: json['status'] as String,
        shopId: json['shop'] as int,
        shopName: json['shop_name'] as String? ?? '',
        shopLogo: json['shop_logo'] as String?,
        slotType: json['slot_type'] as String? ?? 'asap',
        total: double.tryParse('${json['total']}') ?? 0,
        createdAt: DateTime.tryParse('${json['created_at']}'),
      );

  final int id;
  final String number;
  final String status;
  final int shopId;
  final String shopName;
  final String? shopLogo;
  final String slotType;
  final double total;
  final DateTime? createdAt;
}

/// Позиция заказа (`items[]` в деталях).
class OrderItem {
  const OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.price,
    required this.qty,
    this.photoUrl,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        id: json['id'] as int,
        productId: json['product'] as int,
        productName: json['product_name'] as String,
        price: double.tryParse('${json['price']}') ?? 0,
        qty: json['qty'] as int,
        photoUrl: json['photo_url'] as String?,
      );

  final int id;
  final int productId;
  final String productName;
  final double price;
  final int qty;
  final String? photoUrl;

  double get lineTotal => price * qty;
}

/// Запись истории статусов заказа.
class OrderStatusEntry {
  const OrderStatusEntry({required this.status, this.comment, this.at});

  factory OrderStatusEntry.fromJson(Map<String, dynamic> json) =>
      OrderStatusEntry(
        status: json['status'] as String,
        comment: json['comment'] as String?,
        at: DateTime.tryParse('${json['created_at']}'),
      );

  final String status;
  final String? comment;
  final DateTime? at;
}

/// Адрес доставки из деталей заказа.
class OrderAddress {
  const OrderAddress({required this.addressText, this.lat, this.lng, this.details});

  factory OrderAddress.fromJson(Map<String, dynamic> json) => OrderAddress(
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

/// Курьер из деталей заказа (поле `courier`, опционально —
/// backend пока не отдаёт; карточка курьера появится сама, когда начнёт).
class OrderCourier {
  const OrderCourier({required this.name, this.phone});

  factory OrderCourier.fromJson(Map<String, dynamic> json) => OrderCourier(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
      );

  final String name;
  final String? phone;
}

/// Фото собранного букета от магазина (`bouquet_photo` в деталях заказа,
/// api.md §5). `approved == null` — ждёт реакции клиента.
class BouquetPhoto {
  const BouquetPhoto({required this.url, this.approved});

  factory BouquetPhoto.fromJson(Map<String, dynamic> json) => BouquetPhoto(
        url: json['url'] as String? ?? '',
        approved: json['approved'] as bool?,
      );

  final String url;
  final bool? approved;

  bool get awaitingResponse => approved == null;
}

/// Детали заказа из `GET /orders/{id}/`.
class OrderDetail extends OrderSummary {
  const OrderDetail({
    required super.id,
    required super.number,
    required super.status,
    required super.shopId,
    required super.shopName,
    required super.slotType,
    required super.total,
    super.createdAt,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.isAnonymous,
    required this.recipientName,
    required this.recipientPhone,
    required this.statusHistory,
    this.address,
    this.cardText = '',
    this.comment = '',
    this.deliveryPin,
    this.scheduledAt,
    this.cancelReason,
    this.courier,
    this.bouquetPhoto,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
        id: json['id'] as int,
        number: json['number'] as String,
        status: json['status'] as String,
        shopId: json['shop'] as int,
        shopName: json['shop_name'] as String? ?? '',
        slotType: json['slot_type'] as String? ?? 'asap',
        total: double.tryParse('${json['total']}') ?? 0,
        createdAt: DateTime.tryParse('${json['created_at']}'),
        items: (json['items'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(OrderItem.fromJson)
            .toList(),
        subtotal: double.tryParse('${json['subtotal']}') ?? 0,
        deliveryFee: double.tryParse('${json['delivery_fee']}') ?? 0,
        discount: double.tryParse('${json['discount']}') ?? 0,
        isAnonymous: json['is_anonymous'] as bool? ?? false,
        recipientName: json['recipient_name'] as String? ?? '',
        recipientPhone: json['recipient_phone'] as String? ?? '',
        cardText: json['card_text'] as String? ?? '',
        comment: json['comment'] as String? ?? '',
        deliveryPin: json['delivery_pin'] as String?,
        scheduledAt: DateTime.tryParse('${json['scheduled_at']}'),
        cancelReason: json['cancel_reason'] as String?,
        address: json['address'] is Map<String, dynamic>
            ? OrderAddress.fromJson(json['address'] as Map<String, dynamic>)
            : null,
        courier: json['courier'] is Map<String, dynamic>
            ? OrderCourier.fromJson(json['courier'] as Map<String, dynamic>)
            : null,
        bouquetPhoto: json['bouquet_photo'] is Map<String, dynamic>
            ? BouquetPhoto.fromJson(json['bouquet_photo'] as Map<String, dynamic>)
            : null,
        statusHistory: (json['status_history'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(OrderStatusEntry.fromJson)
            .toList(),
      );

  final List<OrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final bool isAnonymous;
  final String recipientName;
  final String recipientPhone;
  final String cardText;
  final String comment;
  final String? deliveryPin;
  final DateTime? scheduledAt;
  final String? cancelReason;
  final OrderAddress? address;
  final OrderCourier? courier;
  final BouquetPhoto? bouquetPhoto;
  final List<OrderStatusEntry> statusHistory;
}

/// Ответ `POST /orders/` (201): заказ создан и ждёт оплаты.
class CreatedOrder {
  const CreatedOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
  });

  factory CreatedOrder.fromJson(Map<String, dynamic> json) => CreatedOrder(
        id: json['id'] as int,
        number: json['number'] as String,
        status: json['status'] as String,
        total: double.tryParse('${json['total']}') ?? 0,
      );

  final int id;
  final String number;
  final String status;
  final double total;
}

/// Ответ `POST /orders/{id}/pay/`.
class PaymentResult {
  const PaymentResult({
    required this.paymentId,
    required this.provider,
    required this.amount,
    required this.status,
  });

  factory PaymentResult.fromJson(Map<String, dynamic> json) => PaymentResult(
        paymentId: json['payment_id'] as int,
        provider: json['provider'] as String? ?? '',
        amount: double.tryParse('${json['amount']}') ?? 0,
        status: json['status'] as String? ?? '',
      );

  final int paymentId;
  final String provider;
  final double amount;
  final String status;

  bool get isSuccess => status == 'success';
}

/// Человекочитаемые метки статусов (зеркало backend Order.Status).
String orderStatusLabel(String status) => switch (status) {
      'created' => 'Ожидает оплаты',
      'payment_failed' => 'Ошибка оплаты',
      'expired' => 'Истёк (не оплачен)',
      'paid' => 'Оплачен',
      'shop_pending' => 'Ждёт магазин',
      'accepted' => 'Принят магазином',
      'rejected' => 'Отклонён магазином',
      'timeout' => 'Таймаут магазина',
      'preparing' => 'Собирается',
      'ready' => 'Готов',
      'courier_assigned' => 'Курьер назначен',
      'picked_up' => 'Забран курьером',
      'on_the_way' => 'В пути',
      'arrived' => 'Курьер на месте',
      'delivered' => 'Доставлен',
      'completed' => 'Завершён',
      'cancelled_client' => 'Отменён вами',
      'cancelled_shop' => 'Отменён магазином',
      'cancelled_admin' => 'Отменён платформой',
      'disputed' => 'Спор',
      _ => status,
    };

/// Финальные статусы (заказ в истории, дальше не двигается).
bool orderStatusIsFinal(String status) => const {
      'expired',
      'payment_failed',
      'rejected',
      'timeout',
      'delivered',
      'completed',
      'cancelled_client',
      'cancelled_shop',
      'cancelled_admin',
      'disputed',
    }.contains(status);

/// Статусы, в которых идёт живая геопозиция курьера (LIVE-бейдж, api.md §7).
bool orderStatusIsTrackable(String status) =>
    const {'picked_up', 'on_the_way', 'arrived'}.contains(status);

/// Крупный заголовок статус-блока на экране заказа (макет 06-tracking).
String orderStatusHeadline(String status) => switch (status) {
      'created' => 'Ожидает оплаты',
      'paid' || 'shop_pending' => 'Передаём заказ в магазин',
      'accepted' || 'preparing' => 'Магазин собирает букет',
      'ready' => 'Букет готов',
      'courier_assigned' => 'Курьер едет в магазин',
      'picked_up' || 'on_the_way' => 'Курьер в пути',
      'arrived' => 'Курьер у двери',
      'delivered' => 'Заказ доставлен',
      'completed' => 'Заказ завершён',
      _ => orderStatusLabel(status),
    };

/// Пояснение под заголовком статуса (null — без пояснения).
String? orderStatusDescription(String status) => switch (status) {
      'paid' || 'shop_pending' => 'Ждём подтверждения от магазина',
      'accepted' || 'preparing' => 'Обычно сборка занимает 15–20 минут',
      'ready' => 'Ищем свободного курьера',
      'courier_assigned' => 'Курьер заберёт букет и поедет к вам',
      'picked_up' || 'on_the_way' => 'Следите за курьером на карте',
      'arrived' => 'Назовите курьеру PIN-код из карточки ниже',
      _ => null,
    };
