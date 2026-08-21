import 'dart:async';

import 'package:flowers_client/src/api/models/user.dart';
import 'package:flowers_client/src/auth/auth_repository.dart';
import 'package:flowers_client/src/auth/token_storage.dart';
import 'package:flowers_client/src/courier/courier_ws.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('parseCourierWsMessage', () {
    test('order_available: id заказа (тонкий payload, лишние поля игнорируются)',
        () {
      final event = parseCourierWsMessage(
        '{"type": "order_available", "order_id": 12, '
        '"shop": {"id": 1, "name": "Флора"}, "delivery_fee": "11.27", '
        '"distance": 187}',
      );
      expect(event, isA<CourierOrderAvailable>());
      expect((event! as CourierOrderAvailable).orderId, 12);
    });

    test('order_taken: id заказа', () {
      final event = parseCourierWsMessage(
        '{"type": "order_taken", "order_id": 12}',
      );
      expect(event, isA<CourierOrderTaken>());
      expect((event! as CourierOrderTaken).orderId, 12);
    });

    test('мусор, чужие типы и битые поля — пропуск (null)', () {
      expect(parseCourierWsMessage('не json'), isNull);
      expect(parseCourierWsMessage('[1, 2]'), isNull);
      expect(parseCourierWsMessage('{"type": "status_changed", "status": "x"}'),
          isNull);
      expect(parseCourierWsMessage('{"type": "order_available"}'), isNull);
      expect(
        parseCourierWsMessage('{"type": "order_taken", "order_id": "12"}'),
        isNull,
      );
    });
  });

  group('CourierWsService', () {
    late TokenStorage tokenStorage;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'auth.access': 'access-1',
        'auth.refresh': 'refresh-1',
      });
      tokenStorage = TokenStorage();
    });

    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('условие не наступило за 3 секунды');
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    test('подключается и отдаёт события order_available/order_taken', () async {
      final controller = StreamController<dynamic>();
      final service = CourierWsService(
        tokenStorage: tokenStorage,
        authRepository: _FakeAuthRepository(),
        connector: (_) async => _FakeWebSocketChannel(controller),
        wsBaseUrl: 'ws://test',
        backoff: const [Duration.zero],
      );
      final events = <CourierWsEvent>[];
      final sub = service.events.listen(events.add);
      service.start();

      await waitFor(() => events.any((e) => e is CourierWsConnectionChanged));
      expect(
        events.first,
        isA<CourierWsConnectionChanged>()
            .having((e) => e.isLive, 'isLive', isTrue),
      );

      controller.add('{"type": "order_available", "order_id": 7}');
      controller.add('{"type": "order_taken", "order_id": 7}');
      controller.add('{"type": "unknown"}');

      await waitFor(() => events.length >= 3);
      expect(events[1], isA<CourierOrderAvailable>());
      expect(events[2], isA<CourierOrderTaken>());
      expect(events, hasLength(3));

      await sub.cancel();
      await controller.close();
      await service.dispose();
    });

    test('переподключается после обрыва канала', () async {
      final controllers = <StreamController<dynamic>>[];
      final service = CourierWsService(
        tokenStorage: tokenStorage,
        authRepository: _FakeAuthRepository(),
        connector: (_) async {
          final controller = StreamController<dynamic>();
          controllers.add(controller);
          return _FakeWebSocketChannel(controller);
        },
        wsBaseUrl: 'ws://test',
        backoff: const [Duration.zero],
      );
      final liveStates = <bool>[];
      final sub = service.events.listen((event) {
        if (event is CourierWsConnectionChanged) liveStates.add(event.isLive);
      });
      service.start();

      await waitFor(() => controllers.length == 1);
      unawaited(controllers.first.close());
      await waitFor(() => controllers.length == 2);

      expect(liveStates, [true, false, true]);

      await sub.cancel();
      await controllers.last.close();
      await service.dispose();
    });
  });
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthTokens> refresh(String refreshToken) async =>
      const AuthTokens(access: 'a2', refresh: 'r2');

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
