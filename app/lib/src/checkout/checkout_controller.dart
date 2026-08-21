import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/models/order.dart';
import '../cart/cart_controller.dart';

/// Контроллер оформления заказа (макет 04-checkout).
///
/// Idempotency-Key генерируется ОДИН на попытку оформления (на вход в экран)
/// и НЕ меняется при повторных тапах «Перейти к оплате» — сервер по тому же
/// ключу вернёт уже созданный заказ вместо дубликата (api.md §3).
class CheckoutController extends ChangeNotifier {
  CheckoutController({
    required ApiClient apiClient,
    String Function()? idGenerator,
  })  : _apiClient = apiClient,
        _idGenerator = idGenerator ?? const Uuid().v4;

  final ApiClient _apiClient;
  final String Function() _idGenerator;

  String? _idempotencyKey;

  /// Ключ идемпотентности текущей попытки: стабилен между вызовами.
  String get idempotencyKey => _idempotencyKey ??= _idGenerator();

  /// Начать новую попытку оформления (например, повторный вход на экран
  /// после успешного заказа) — следующий заказ получит новый ключ.
  void renewIdempotencyKey() {
    _idempotencyKey = null;
  }

  bool _submitting = false;
  bool get submitting => _submitting;

  /// `POST /orders/` с телом по спеке. Ошибки сервера (shop_closed,
  /// out_of_zone, promo_invalid, min_order…) прилетают как ApiException —
  /// их message человекочитаемое, показываем как есть.
  Future<CreatedOrder> submit({
    required CartController cart,
    required String recipientName,
    required String recipientPhone,
    required bool isAnonymous,
    required String slotType,
    DateTime? scheduledAt,
    String cardText = '',
    String comment = '',
    String promoCode = '',
  }) async {
    if (_submitting) throw StateError('Уже отправляется');
    _submitting = true;
    notifyListeners();
    try {
      final body = <String, dynamic>{
        'shop_id': cart.shopId,
        'items': [
          for (final item in cart.items)
            {'product_id': item.product.id, 'qty': item.qty},
        ],
        'card_text': cardText.trim(),
        'is_anonymous': isAnonymous,
        'recipient_name': recipientName.trim(),
        'recipient_phone': recipientPhone,
        // TODO(геолокация): статичный пресет адреса, заменить на выбор
        // адреса/карту, когда появится геолокация.
        'address': {
          'lat': 38.5598,
          'lng': 68.7870,
          'address_text': 'ул. Рудаки 25',
        },
        'slot_type': slotType,
        if (slotType == 'scheduled' && scheduledAt != null)
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
        if (promoCode.trim().isNotEmpty) 'promo_code': promoCode.trim(),
        'comment': comment.trim(),
      };
      return await _apiClient.createOrder(
        body: body,
        idempotencyKey: idempotencyKey,
      );
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }
}
