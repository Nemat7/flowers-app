import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/config.dart' show kWsBaseUrl;
import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';

/// События живого трекинга заказа (канал /ws/client/orders/{id}/, api.md §7).
sealed class OrderTrackingEvent {
  const OrderTrackingEvent();
}

/// `status_changed {order_id, status, at}` — смена статуса заказа.
class TrackingStatusChanged extends OrderTrackingEvent {
  const TrackingStatusChanged({required this.status, this.at});

  final String status;
  final DateTime? at;
}

/// `courier_location {lat, lng}` — живая позиция курьера
/// (шлётся, пока заказ в picked_up..arrived).
class TrackingCourierLocation extends OrderTrackingEvent {
  const TrackingCourierLocation({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

/// `bouquet_photo {photo_url}` — магазин прислал фото собранного букета
/// на одобрение (api.md §5). Экран заказа делает тихий refetch деталей.
class TrackingBouquetPhoto extends OrderTrackingEvent {
  const TrackingBouquetPhoto({required this.photoUrl});

  final String photoUrl;
}

/// Смена состояния транспорта: `isLive` — WS подключён и шлёт события,
/// иначе работает fallback-polling (или связь потеряна).
class TrackingConnectionChanged extends OrderTrackingEvent {
  const TrackingConnectionChanged({required this.isLive});

  final bool isLive;
}

/// Разбор одного WS-сообщения. Неизвестный тип или мусор — null (пропуск).
OrderTrackingEvent? parseTrackingMessage(dynamic raw) {
  final dynamic decoded;
  try {
    decoded = raw is String ? jsonDecode(raw) : raw;
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  return switch (decoded['type']) {
    'status_changed' => _parseStatusChanged(decoded),
    'courier_location' => _parseCourierLocation(decoded),
    'bouquet_photo' => _parseBouquetPhoto(decoded),
    _ => null,
  };
}

TrackingStatusChanged? _parseStatusChanged(Map<String, dynamic> json) {
  final status = json['status'];
  if (status is! String) return null;
  return TrackingStatusChanged(
    status: status,
    at: DateTime.tryParse('${json['at']}'),
  );
}

TrackingCourierLocation? _parseCourierLocation(Map<String, dynamic> json) {
  final lat = json['lat'];
  final lng = json['lng'];
  if (lat is! num || lng is! num) return null;
  return TrackingCourierLocation(lat: lat.toDouble(), lng: lng.toDouble());
}

TrackingBouquetPhoto? _parseBouquetPhoto(Map<String, dynamic> json) {
  final photoUrl = json['photo_url'];
  if (photoUrl is! String || photoUrl.isEmpty) return null;
  return TrackingBouquetPhoto(photoUrl: photoUrl);
}

typedef TrackingChannelConnector = Future<WebSocketChannel> Function(Uri uri);

/// Живой трекинг заказа: WS `/ws/client/orders/{id}/?token=<access>`.
///
/// Авто-reconnect с backoff (1s→2s→5s→15s), перед повторным подключением
/// обновляет access-токен через [AuthRepository]. Если WS не поднялся после
/// [maxAttempts] подряд неудачных попыток — fallback на polling
/// `GET /orders/{id}/` (через [pollStatus]) каждые [pollInterval]:
/// наружу идут те же [TrackingStatusChanged], UI разницы не замечает.
class OrderTrackingService {
  OrderTrackingService({
    required this.orderId,
    required TokenStorage tokenStorage,
    required AuthRepository authRepository,
    Future<String?> Function()? pollStatus,
    TrackingChannelConnector? connector,
    String? initialStatus,
    String wsBaseUrl = kWsBaseUrl,
    this.maxAttempts = 3,
    this.pollInterval = const Duration(seconds: 10),
    List<Duration> backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ],
  })  : _tokenStorage = tokenStorage,
        _authRepository = authRepository,
        _pollStatus = pollStatus,
        _connector =
            connector ?? ((uri) async => WebSocketChannel.connect(uri)),
        _wsBaseUrl = wsBaseUrl,
        _backoff = backoff,
        _lastPolledStatus = initialStatus;

  final int orderId;

  /// Максимум подряд неудачных connect до перехода на polling.
  final int maxAttempts;

  final Duration pollInterval;

  final TokenStorage _tokenStorage;
  final AuthRepository _authRepository;
  final Future<String?> Function()? _pollStatus;
  final TrackingChannelConnector _connector;
  final String _wsBaseUrl;
  final List<Duration> _backoff;

  final _events = StreamController<OrderTrackingEvent>.broadcast();
  Stream<OrderTrackingEvent> get events => _events.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pollTimer;
  String? _lastPolledStatus;
  bool _disposed = false;

  void start() {
    _run();
  }

  Future<void> _run() async {
    var failures = 0;
    while (!_disposed) {
      try {
        if (failures > 0) await _refreshToken();
        final tokens = await _tokenStorage.readTokens();
        final uri = Uri.parse(
          '$_wsBaseUrl/ws/client/orders/$orderId/?token=${tokens?.access}',
        );
        final channel = await _connector(uri);
        if (_disposed) {
          unawaited(channel.sink.close());
          return;
        }
        _channel = channel;
        failures = 0;
        _emit(const TrackingConnectionChanged(isLive: true));
        await _listen(channel);
        _channel = null;
        if (_disposed) return;
        // Соединение оборвалось — ждём backoff и переподключаемся.
        _emit(const TrackingConnectionChanged(isLive: false));
        failures++;
      } catch (_) {
        if (_disposed) return;
        failures++;
      }
      if (failures >= maxAttempts) {
        _startPolling();
        return;
      }
      await Future<void>.delayed(_delayFor(failures));
    }
  }

  Duration _delayFor(int failures) =>
      _backoff[(failures - 1).clamp(0, _backoff.length - 1)];

  Future<void> _listen(WebSocketChannel channel) {
    final done = Completer<void>();
    _subscription = channel.stream.listen(
      (message) {
        final event = parseTrackingMessage(message);
        if (event != null) _emit(event);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (_) {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  // ---------------- fallback: polling REST ----------------

  void _startPolling() {
    _emit(const TrackingConnectionChanged(isLive: false));
    _poll();
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final fetch = _pollStatus;
    if (fetch == null || _disposed) return;
    try {
      final status = await fetch();
      if (_disposed || status == null || status == _lastPolledStatus) return;
      _lastPolledStatus = status;
      _emit(TrackingStatusChanged(status: status, at: DateTime.now()));
    } catch (_) {
      // Сеть мигает — следующий тик попробует снова.
    }
  }

  /// Access мог протухнуть за время backoff — обновляем best-effort.
  Future<void> _refreshToken() async {
    try {
      final refresh = await _tokenStorage.readRefreshToken();
      if (refresh == null) return;
      final tokens = await _authRepository.refresh(refresh);
      await _tokenStorage.saveTokens(tokens);
    } catch (_) {
      // Не получилось — попробуем подключиться со старым токеном.
    }
  }

  void _emit(OrderTrackingEvent event) {
    if (!_disposed) _events.add(event);
  }

  Future<void> dispose() async {
    _disposed = true;
    _pollTimer?.cancel();
    await _subscription?.cancel();
    unawaited(_channel?.sink.close());
    await _events.close();
  }
}
