import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/config.dart' show kWsBaseUrl;
import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';

/// События курьерского канала /ws/courier/ (api.md §7).
sealed class CourierWsEvent {
  const CourierWsEvent();
}

/// `order_available {order_id, shop, delivery_fee, distance}` — новый заказ
/// ready в зоне. Payload «тонкий» (без адреса/получателя), поэтому
/// контроллер по этому событию просто перечитывает GET available.
class CourierOrderAvailable extends CourierWsEvent {
  const CourierOrderAvailable({required this.orderId});

  final int orderId;
}

/// `order_taken {order_id}` — заказ ушёл другому курьеру.
class CourierOrderTaken extends CourierWsEvent {
  const CourierOrderTaken({required this.orderId});

  final int orderId;
}

/// Смена состояния транспорта: `isLive` — WS подключён.
class CourierWsConnectionChanged extends CourierWsEvent {
  const CourierWsConnectionChanged({required this.isLive});

  final bool isLive;
}

/// Разбор одного WS-сообщения. Неизвестный тип или мусор — null (пропуск).
CourierWsEvent? parseCourierWsMessage(dynamic raw) {
  final dynamic decoded;
  try {
    decoded = raw is String ? jsonDecode(raw) : raw;
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final orderId = decoded['order_id'];
  return switch (decoded['type']) {
    'order_available' when orderId is int =>
      CourierOrderAvailable(orderId: orderId),
    'order_taken' when orderId is int => CourierOrderTaken(orderId: orderId),
    _ => null,
  };
}

typedef CourierChannelConnector = Future<WebSocketChannel> Function(Uri uri);

/// Курьерский WS `/ws/courier/?token=<access>`: доступные заказы в реальном
/// времени. Подключается, пока курьер на линии; reconnect с backoff
/// (1s→2s→5s→15s) по образцу OrderTrackingService. Fallback на случай
/// мёртвого WS — polling GET available в CourierController (15 сек),
/// здесь его нет: сервис отвечает только за живой канал.
class CourierWsService {
  CourierWsService({
    required TokenStorage tokenStorage,
    required AuthRepository authRepository,
    CourierChannelConnector? connector,
    String wsBaseUrl = kWsBaseUrl,
    List<Duration> backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ],
  })  : _tokenStorage = tokenStorage,
        _authRepository = authRepository,
        _connector =
            connector ?? ((uri) async => WebSocketChannel.connect(uri)),
        _wsBaseUrl = wsBaseUrl,
        _backoff = backoff;

  final TokenStorage _tokenStorage;
  final AuthRepository _authRepository;
  final CourierChannelConnector _connector;
  final String _wsBaseUrl;
  final List<Duration> _backoff;

  final _events = StreamController<CourierWsEvent>.broadcast();
  Stream<CourierWsEvent> get events => _events.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
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
          '$_wsBaseUrl/ws/courier/?token=${tokens?.access}',
        );
        final channel = await _connector(uri);
        if (_disposed) {
          unawaited(channel.sink.close());
          return;
        }
        _channel = channel;
        failures = 0;
        _emit(const CourierWsConnectionChanged(isLive: true));
        await _listen(channel);
        _channel = null;
        if (_disposed) return;
        _emit(const CourierWsConnectionChanged(isLive: false));
        failures++;
      } catch (_) {
        if (_disposed) return;
        failures++;
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
        final event = parseCourierWsMessage(message);
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

  void _emit(CourierWsEvent event) {
    if (!_disposed) _events.add(event);
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    unawaited(_channel?.sink.close());
    await _events.close();
  }
}
