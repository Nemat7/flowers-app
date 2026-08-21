import 'dart:async';

import 'package:flowers_client/src/api/models/user.dart';
import 'package:flowers_client/src/auth/auth_repository.dart';
import 'package:flowers_client/src/auth/token_storage.dart';
import 'package:flowers_client/src/orders/tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('parseTrackingMessage', () {
    test('status_changed: статус и время (лишние поля игнорируются)', () {
      final event = parseTrackingMessage(
        '{"type": "status_changed", "order_id": 9, '
        '"status": "on_the_way", "at": "2026-08-07T16:06:41.967144+00:00"}',
      );
      expect(event, isA<TrackingStatusChanged>());
      final statusChanged = event! as TrackingStatusChanged;
      expect(statusChanged.status, 'on_the_way');
      expect(statusChanged.at, isNotNull);
    });

    test('courier_location: lat/lng в double', () {
      final event = parseTrackingMessage(
        '{"type": "courier_location", "lat": 38.5605, "lng": 68.788}',
      );
      expect(event, isA<TrackingCourierLocation>());
      final location = event! as TrackingCourierLocation;
      expect(location.lat, closeTo(38.5605, 1e-9));
      expect(location.lng, closeTo(68.788, 1e-9));
    });

    test('bouquet_photo: ссылка на фото; пустая — пропуск', () {
      final event = parseTrackingMessage(
        '{"type": "bouquet_photo", "order_id": 9, '
        '"photo_url": "http://localhost:8002/media/order_photos/1.jpg"}',
      );
      expect(event, isA<TrackingBouquetPhoto>());
      final photo = event! as TrackingBouquetPhoto;
      expect(photo.photoUrl, endsWith('/media/order_photos/1.jpg'));

      expect(
        parseTrackingMessage('{"type": "bouquet_photo", "photo_url": ""}'),
        isNull,
      );
      expect(parseTrackingMessage('{"type": "bouquet_photo"}'), isNull);
    });

    test('неизвестный тип события — пропуск (null)', () {
      expect(parseTrackingMessage('{"type": "new_order", "order_id": 9}'), isNull);
      expect(parseTrackingMessage('{"type": "order_taken"}'), isNull);
    });

    test('мусор и битые поля — пропуск (null)', () {
      expect(parseTrackingMessage('не json'), isNull);
      expect(parseTrackingMessage('[1, 2]'), isNull);
      expect(parseTrackingMessage('{"type": "status_changed"}'), isNull);
      expect(
        parseTrackingMessage('{"type": "courier_location", "lat": "x", "lng": 68.7}'),
        isNull,
      );
    });
  });

  group('OrderTrackingService', () {
    late TokenStorage tokenStorage;
    late _FakeAuthRepository authRepository;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth.access': 'access-1',
        'auth.refresh': 'refresh-1',
      });
      tokenStorage = TokenStorage();
      authRepository = _FakeAuthRepository();
    });

    /// Ждать выполнения условия (события приходят из таймеров/стримов).
    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('условие не наступило за 3 секунды');
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    OrderTrackingService buildService({
      required TrackingChannelConnector connector,
      Future<String?> Function()? pollStatus,
      String? initialStatus,
    }) {
      return OrderTrackingService(
        orderId: 9,
        tokenStorage: tokenStorage,
        authRepository: authRepository,
        connector: connector,
        pollStatus: pollStatus,
        initialStatus: initialStatus,
        wsBaseUrl: 'ws://test',
        backoff: const [Duration.zero],
        pollInterval: const Duration(milliseconds: 10),
      );
    }

    test('подключается к WS и отдаёт распарсенные события', () async {
      final controller = StreamController<dynamic>();
      final service = buildService(
        connector: (_) async => _FakeWebSocketChannel(controller),
      );
      final events = <OrderTrackingEvent>[];
      final sub = service.events.listen(events.add);
      service.start();

      await waitFor(() => events.any((e) => e is TrackingConnectionChanged));
      expect(
        events.first,
        isA<TrackingConnectionChanged>()
            .having((e) => e.isLive, 'isLive', isTrue),
      );

      controller.add(
        '{"type": "status_changed", "order_id": 9, "status": "ready", '
        '"at": "2026-08-07T16:06:41.785836+00:00"}',
      );
      controller.add('{"type": "courier_location", "lat": 38.5605, "lng": 68.788}');
      controller.add('{"type": "unknown_event"}');

      await waitFor(() => events.length >= 3);
      expect(events[1], isA<TrackingStatusChanged>());
      expect(events[2], isA<TrackingCourierLocation>());
      // неизвестное событие пропущено — лишних нет
      expect(events, hasLength(3));

      await sub.cancel();
      await controller.close();
      await service.dispose();
    });

    test('переподключается после обрыва канала (с refresh токена)', () async {
      final controllers = <StreamController<dynamic>>[];
      final service = buildService(
        connector: (_) async {
          final controller = StreamController<dynamic>();
          controllers.add(controller);
          return _FakeWebSocketChannel(controller);
        },
      );
      final liveStates = <bool>[];
      final sub = service.events.listen((event) {
        if (event is TrackingConnectionChanged) liveStates.add(event.isLive);
      });
      service.start();

      await waitFor(() => controllers.length == 1);
      // Сервер закрыл соединение — ждём reconnect.
      unawaited(controllers.first.close());
      await waitFor(() => controllers.length == 2);

      expect(liveStates, [true, false, true]);
      expect(authRepository.refreshCalls, greaterThanOrEqualTo(1));

      await sub.cancel();
      await controllers.last.close();
      await service.dispose();
    });

    test('после 3 неудачных connect — fallback на polling', () async {
      var connectAttempts = 0;
      final polledStatuses = ['ready', 'ready', 'picked_up'];
      var pollCalls = 0;
      final service = buildService(
        initialStatus: 'preparing',
        connector: (_) async {
          connectAttempts++;
          throw WebSocketChannelException('сервер недоступен');
        },
        pollStatus: () async {
          final status =
              polledStatuses[pollCalls.clamp(0, polledStatuses.length - 1)];
          pollCalls++;
          return status;
        },
      );
      final events = <OrderTrackingEvent>[];
      final sub = service.events.listen(events.add);
      service.start();

      // 3 неудачных connect → ConnectionChanged(false) → polling.
      await waitFor(
        () => events.any(
          (e) => e is TrackingConnectionChanged && !e.isLive,
        ),
      );
      expect(connectAttempts, 3);

      // polling прислал изменение статуса тем же TrackingStatusChanged.
      await waitFor(
        () => events
            .whereType<TrackingStatusChanged>()
            .any((e) => e.status == 'picked_up'),
      );
      final statuses = events
          .whereType<TrackingStatusChanged>()
          .map((e) => e.status)
          .toList();
      expect(statuses, containsAllInOrder(['ready', 'picked_up']));
      // initialStatus='preparing' не эмитится как «изменение».
      expect(statuses, isNot(contains('preparing')));

      await sub.cancel();
      await service.dispose();
    });
  });
}

class _FakeAuthRepository implements AuthRepository {
  int refreshCalls = 0;

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    refreshCalls++;
    return AuthTokens(access: 'access-${refreshCalls + 1}', refresh: 'refresh-1');
  }

  @override
  Future<OtpRequestResult> requestOtp(String phone) =>
      throw UnimplementedError();

  @override
  Future<AuthSession> verifyOtp({required String phone, required String code}) =>
      throw UnimplementedError();

  @override
  Future<User> fetchMe(String accessToken) => throw UnimplementedError();

  @override
  Future<void> logout(String refreshToken) => throw UnimplementedError();
}

/// Канал поверх StreamController: тест пушит «сообщения сервера» сам.
class _FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _FakeWebSocketChannel(this._controller);

  final StreamController<dynamic> _controller;
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future<void>.value();
}

class _FakeWebSocketSink implements WebSocketSink {
  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future<void>.value();
}
