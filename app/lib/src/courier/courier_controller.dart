import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/courier.dart';
import 'courier_ws.dart';
import 'location_tracker.dart';

/// Шаг активного заказа — по одному действию на экране (курьер за рулём).
enum CourierStep {
  /// courier_assigned — едем в магазин, кнопка «Забрал заказ».
  toShop,

  /// picked_up/on_the_way — едем к получателю, кнопка «Я на месте».
  toRecipient,

  /// arrived — ввод PIN получателя, кнопка «Завершить».
  confirmPin,
}

/// Статусы, в которых идёт GPS-трекинг (POST /courier/location/, api.md §6).
bool courierStatusIsTrackable(String status) =>
    const {'picked_up', 'on_the_way', 'arrived'}.contains(status);

CourierStep courierStepForStatus(String status) => switch (status) {
      'courier_assigned' => CourierStep.toShop,
      'arrived' => CourierStep.confirmPin,
      _ => CourierStep.toRecipient,
    };

/// Состояние экрана «Заказы» курьера: линия, доступные заказы,
/// активный заказ с шагами, GPS-трекинг, WS + polling-fallback.
///
/// Стейт-машина шагов: accept → (courier_assigned) → pickup → (on_the_way)
/// → arrive → (arrived) → complete(pin). Неверный PIN (400 invalid_pin)
/// не меняет состояние — только показывает ошибку под полем.
class CourierController extends ChangeNotifier {
  CourierController({
    required ApiClient apiClient,
    CourierWsService? wsService,
    PositionStreamFactory? positionStream,
    this.pollInterval = const Duration(seconds: 15),
  })  : _api = apiClient,
        _ws = wsService,
        _positionStream = positionStream;

  final ApiClient _api;
  final CourierWsService? _ws;
  final PositionStreamFactory? _positionStream;

  /// Polling доступных заказов — fallback к WS (api.md §7).
  final Duration pollInterval;

  /// Статус профиля: offline / online / busy (busy = активный заказ,
  /// выставляется сервером; для UI busy ≈ online).
  String lineStatus = 'offline';

  CourierOrder? current;
  List<CourierOrder> available = const [];

  bool loading = true;
  String? loadError;

  /// Шаг выполняется (accept/pickup/arrive/complete) — блокируем кнопки.
  bool actionInProgress = false;

  /// Ошибка PIN (invalid_pin) — показывается под полем, состояние не сбрасывается.
  String? pinError;

  /// Одноразовое сообщение для snackbar (order_taken, ошибки действий).
  String? notice;

  /// Нет разрешения на геолокацию — предупреждение на карточке заказа
  /// (шаги не блокируются).
  bool locationWarning = false;

  /// WS /ws/courier/ подключён (иначе работает только polling).
  bool wsLive = false;

  StreamSubscription<CourierWsEvent>? _wsSubscription;
  Timer? _pollTimer;
  LocationTracker? _tracker;

  bool get isOnLine => lineStatus != 'offline';

  CourierStep? get step =>
      current == null ? null : courierStepForStatus(current!.status);

  void clearNotice() {
    notice = null;
  }

  /// Старт экрана: есть ли активный заказ. Статус линии сервер не отдаёт
  /// (GET /courier/status/ в спеке нет) — считаем себя offline, пока курьер
  /// не выйдет на линию переключателем; busy восстанавливаем по current.
  Future<void> init() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      current = await _api.fetchCourierCurrentOrder();
      if (current != null) {
        lineStatus = 'busy';
        _connectLive();
        _startTrackingIfNeeded();
      }
      loading = false;
    } on ApiException catch (e) {
      loadError = e.message;
      loading = false;
    }
    notifyListeners();
  }

  // ---------------- линия (online/offline) ----------------

  /// Переключатель «На линии». Offline при активном заказе — сервер
  /// отвечает 409 active_delivery: показываем его сообщение, остаёмся online.
  Future<void> setOnLine(bool online) async {
    try {
      lineStatus = await _api.setCourierStatus(online ? 'online' : 'offline');
      if (online) {
        _connectLive();
        // Подтянуть фактическое состояние (мог быть busy после перезапуска).
        current = await _api.fetchCourierCurrentOrder();
        _startTrackingIfNeeded();
        await _loadAvailable();
      } else {
        _disconnectLive();
        available = const [];
      }
    } on ApiException catch (e) {
      if (e.code == 'active_delivery') {
        lineStatus = 'busy';
      }
      notice = e.message;
    }
    notifyListeners();
  }

  // ---------------- доступные заказы ----------------

  /// Pull-to-refresh / первичная загрузка списка доступных.
  Future<void> refreshAvailable() => _loadAvailable();

  Future<void> _loadAvailable({bool silent = false}) async {
    try {
      final orders = await _api.fetchCourierAvailableOrders();
      available = orders;
      loadError = null;
    } on ApiException catch (e) {
      if (!silent) loadError = e.message;
    }
    notifyListeners();
  }

  /// Взять заказ. Гонка курьеров: 409 order_taken → snackbar
  /// «Заказ ушёл другому курьеру» + обновление списка.
  Future<void> acceptOrder(int orderId) async {
    if (actionInProgress) return;
    actionInProgress = true;
    notifyListeners();
    try {
      await _api.acceptCourierOrder(orderId);
      current = await _api.fetchCourierCurrentOrder();
      lineStatus = 'busy';
      available = available.where((o) => o.id != orderId).toList();
    } on ApiException catch (e) {
      if (e.code == 'order_taken') {
        notice = 'Заказ ушёл другому курьеру';
        available = available.where((o) => o.id != orderId).toList();
        await _loadAvailable(silent: true);
      } else {
        notice = e.message;
      }
    }
    actionInProgress = false;
    notifyListeners();
  }

  // ---------------- шаги активного заказа ----------------

  /// «Забрал заказ»: courier_assigned → on_the_way, старт GPS-трекинга.
  Future<void> pickupOrder() => _advanceStep(
        (id) => _api.pickupCourierOrder(id),
        afterSuccess: _startTrackingIfNeeded,
      );

  /// «Я на месте»: on_the_way → arrived.
  Future<void> arriveOrder() =>
      _advanceStep((id) => _api.arriveCourierOrder(id));

  Future<void> _advanceStep(
    Future<CourierOrderAction> Function(int orderId) action, {
    VoidCallback? afterSuccess,
  }) async {
    final order = current;
    if (order == null || actionInProgress) return;
    actionInProgress = true;
    notifyListeners();
    try {
      final result = await action(order.id);
      current = order.copyWithStatus(result.status);
      afterSuccess?.call();
    } on ApiException catch (e) {
      notice = e.message;
    }
    actionInProgress = false;
    notifyListeners();
  }

  /// «Завершить» по PIN получателя. Неверный PIN — красное сообщение
  /// под полем, состояние arrived сохраняется (можно ввести ещё раз).
  Future<bool> completeOrder(String pin) async {
    final order = current;
    if (order == null || actionInProgress) return false;
    actionInProgress = true;
    pinError = null;
    notifyListeners();
    var success = false;
    try {
      await _api.completeCourierOrder(order.id, pin: pin);
      current = null;
      pinError = null;
      // Сервер возвращает курьера на линию после доставки.
      lineStatus = 'online';
      success = true;
    } on ApiException catch (e) {
      if (e.code == 'invalid_pin') {
        pinError = e.message;
      } else {
        notice = e.message;
      }
    }
    actionInProgress = false;
    if (success) {
      await _stopTracking();
      locationWarning = false;
      await _loadAvailable(silent: true);
    }
    notifyListeners();
    return success;
  }

  // ---------------- GPS-трекинг ----------------

  /// Идёт GPS-трекинг активной доставки (для UI/тестов).
  bool get isTracking => _tracker != null;

  void _startTrackingIfNeeded() {
    final order = current;
    final positionStream = _positionStream;
    if (order == null ||
        !courierStatusIsTrackable(order.status) ||
        _tracker != null ||
        positionStream == null) {
      return;
    }
    final tracker = LocationTracker(
      positionStream: positionStream,
      send: (points) async => _api.sendCourierLocations(points),
      onError: handleLocationError,
    );
    _tracker = tracker;
    tracker.start();
  }

  Future<void> _stopTracking() async {
    final tracker = _tracker;
    _tracker = null;
    await tracker?.stop();
  }

  /// Вызывается LocationTracker при ошибках источника позиций/отправки.
  /// Ошибки сети (ApiException) молча переживаем — точки остаются в буфере.
  void handleLocationError(Object error) {
    if (error is ApiException) return;
    if (!locationWarning) {
      locationWarning = true;
      notifyListeners();
    }
  }

  // ---------------- WS + polling ----------------

  void _connectLive() {
    final ws = _ws;
    if (ws != null && _wsSubscription == null) {
      _wsSubscription = ws.events.listen(_onWsEvent);
      ws.start();
    }
    _pollTimer ??= Timer.periodic(pollInterval, (_) {
      if (isOnLine && current == null) _loadAvailable(silent: true);
    });
  }

  void _disconnectLive() {
    unawaited(_wsSubscription?.cancel());
    _wsSubscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    wsLive = false;
  }

  void _onWsEvent(CourierWsEvent event) {
    switch (event) {
      case CourierOrderAvailable():
        // Payload события «тонкий» — полную карточку берём по REST.
        if (isOnLine && current == null) _loadAvailable(silent: true);
      case CourierOrderTaken(:final orderId):
        available = available.where((o) => o.id != orderId).toList();
        notifyListeners();
      case CourierWsConnectionChanged(:final isLive):
        wsLive = isLive;
        notifyListeners();
    }
  }

  @override
  void dispose() {
    _disconnectLive();
    unawaited(_stopTracking());
    super.dispose();
  }
}
