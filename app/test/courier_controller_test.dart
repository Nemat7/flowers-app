import 'dart:async';

import 'package:flowers_client/src/api/api_client.dart';
import 'package:flowers_client/src/api/api_error.dart';
import 'package:flowers_client/src/api/models/courier.dart';
import 'package:flowers_client/src/api/models/user.dart';
import 'package:flowers_client/src/api/pagination.dart';
import 'package:flowers_client/src/auth/auth_repository.dart';
import 'package:flowers_client/src/auth/token_storage.dart';
import 'package:flowers_client/src/courier/courier_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeCourierApi api;
  late StreamController<CourierLocationPoint> positions;

  CourierOrder makeOrder({int id = 1, String status = 'ready'}) =>
      CourierOrder.fromJson({
        'id': id,
        'number': 'F-$id',
        'status': status,
        'shop': const {
          'id': 1,
          'name': 'Флора Душанбе',
          'address_text': 'пр. Рудаки 25',
          'lat': 38.5598,
          'lng': 68.787,
        },
        'address': const {
          'lat': 38.565,
          'lng': 68.79,
          'address_text': 'ул. Рудаки 25',
          'details': 'подъезд 2',
        },
        'recipient_name': 'Гульчехра',
        'recipient_phone': '+992900000009',
        'total': '492.77',
        'delivery_fee': '11.27',
        'fee': '11.27',
        'distance': 187,
        'created_at': '2026-08-06T16:31:58.946746+05:00',
      });

  CourierController buildController() => CourierController(
        apiClient: api,
        positionStream: () => positions.stream,
        pollInterval: const Duration(minutes: 5),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth.access': 'access-1',
      'auth.refresh': 'refresh-1',
    });
    api = FakeCourierApi();
    positions = StreamController<CourierLocationPoint>.broadcast();
  });

  tearDown(() async {
    await positions.close();
  });

  group('CourierController: линия и init', () {
    test('init без активного заказа: offline, без списка доступных', () async {
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.init();

      expect(controller.loading, isFalse);
      expect(controller.isOnLine, isFalse);
      expect(controller.current, isNull);
      expect(controller.isTracking, isFalse);
    });

    test('init с активным заказом on_the_way: busy + трекинг запущен',
        () async {
      api.current = makeOrder(status: 'on_the_way');
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.init();

      expect(controller.lineStatus, 'busy');
      expect(controller.step, CourierStep.toRecipient);
      expect(controller.isTracking, isTrue);
    });

    test('offline при активном заказе: 409 active_delivery — остаёмся busy, '
        'сообщение сервера в notice', () async {
      api.current = makeOrder(status: 'courier_assigned');
      api.failOfflineWithActive = true;
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.init();

      await controller.setOnLine(false);

      expect(controller.lineStatus, 'busy');
      expect(controller.isOnLine, isTrue);
      expect(controller.notice, contains('активным заказом'));
    });

    test('выход на линию: статус online, подтягиваются доступные', () async {
      api.available = [makeOrder()];
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.init();

      await controller.setOnLine(true);

      expect(controller.lineStatus, 'online');
      expect(controller.available, hasLength(1));
    });
  });

  group('CourierController: стейт-машина заказа', () {
    test('accept → pickup → arrive → complete: полный путь', () async {
      api.available = [makeOrder()];
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.init();
      await controller.setOnLine(true);

      // accept: заказ становится текущим, курьер busy, трекинга ещё нет.
      await controller.acceptOrder(1);
      expect(controller.current?.status, 'courier_assigned');
      expect(controller.step, CourierStep.toShop);
      expect(controller.lineStatus, 'busy');
      expect(controller.available, isEmpty);
      expect(controller.isTracking, isFalse);

      // pickup: on_the_way, старт GPS-трекинга.
      await controller.pickupOrder();
      expect(controller.current?.status, 'on_the_way');
      expect(controller.step, CourierStep.toRecipient);
      expect(controller.isTracking, isTrue);

      // arrive: arrived, трекинг продолжается.
      await controller.arriveOrder();
      expect(controller.current?.status, 'arrived');
      expect(controller.step, CourierStep.confirmPin);
      expect(controller.isTracking, isTrue);

      // complete с верным PIN: заказ закрыт, курьер снова online.
      final success = await controller.completeOrder('4321');
      expect(success, isTrue);
      expect(controller.current, isNull);
      expect(controller.lineStatus, 'online');
      expect(controller.isTracking, isFalse);
      expect(controller.pinError, isNull);
    });

    test('неверный PIN: invalid_pin — ошибка под полем, состояние не ломается',
        () async {
      api.current = makeOrder(status: 'arrived');
      api.validPin = '4321';
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.init();

      final success = await controller.completeOrder('0000');

      expect(success, isFalse);
      expect(controller.pinError, 'Неверный PIN-код получателя');
      // Состояние не сброшено: тот же шаг, трекинг жив, можно повторить.
      expect(controller.current?.status, 'arrived');
      expect(controller.step, CourierStep.confirmPin);
      expect(controller.isTracking, isTrue);
      expect(controller.actionInProgress, isFalse);

      final retry = await controller.completeOrder('4321');
      expect(retry, isTrue);
      expect(controller.current, isNull);
    });

    test('accept проиграл гонку: 409 order_taken → snackbar + список обновлён',
        () async {
      api.available = [makeOrder(id: 1), makeOrder(id: 2)];
      api.failAcceptWithTaken = true;
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.init();
      await controller.setOnLine(true);

      await controller.acceptOrder(1);

      expect(controller.notice, 'Заказ ушёл другому курьеру');
      expect(controller.current, isNull);
      // Карточка убрана сразу, затем список перечитан с сервера.
      expect(api.availableFetches, greaterThanOrEqualTo(2));
      expect(controller.actionInProgress, isFalse);
    });

    test('complete с неверным PIN не шлёт локации после остановки', () async {
      api.current = makeOrder(status: 'arrived');
      final controller = buildController();
      addTearDown(controller.dispose);
      await controller.init();
      expect(controller.isTracking, isTrue);

      await controller.completeOrder('4321');

      expect(controller.isTracking, isFalse);
      // Точки, пришедшие после complete, никуда не отправляются.
      positions.add(
        CourierLocationPoint(lat: 38.56, lng: 68.78, ts: 1754800000),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(api.sentBatches, isEmpty);
    });
  });
}

/// Фейк ApiClient: только курьерские методы, сеть не используется.
class FakeCourierApi extends ApiClient {
  FakeCourierApi()
      : super(
          tokenStorage: TokenStorage(),
          authRepository: _FakeAuthRepository(),
        );

  String status = 'offline';
  CourierOrder? current;
  List<CourierOrder> available = [];
  bool failOfflineWithActive = false;
  bool failAcceptWithTaken = false;
  String validPin = '4321';
  int availableFetches = 0;
  final sentBatches = <List<CourierLocationPoint>>[];

  @override
  Future<String> setCourierStatus(String target) async {
    if (target == 'offline' && failOfflineWithActive) {
      throw const ApiException(
        code: 'active_delivery',
        message:
            'Нельзя уйти offline с активным заказом — сначала завершите доставку',
        statusCode: 409,
      );
    }
    status = target;
    return current != null ? 'busy' : target;
  }

  @override
  Future<CourierOrder?> fetchCourierCurrentOrder() async => current;

  @override
  Future<List<CourierOrder>> fetchCourierAvailableOrders() async {
    availableFetches++;
    return available;
  }

  @override
  Future<CourierOrderAction> acceptCourierOrder(int id) async {
    if (failAcceptWithTaken) {
      throw const ApiException(
        code: 'order_taken',
        message: 'Заказ уже забрал другой курьер',
        statusCode: 409,
      );
    }
    final order = available.firstWhere((o) => o.id == id);
    current = order.copyWithStatus('courier_assigned');
    available = available.where((o) => o.id != id).toList();
    status = 'busy';
    return CourierOrderAction(id: id, status: current!.status);
  }

  @override
  Future<CourierOrderAction> pickupCourierOrder(int id) async {
    current = current!.copyWithStatus('on_the_way');
    return const CourierOrderAction(id: 1, status: 'on_the_way');
  }

  @override
  Future<CourierOrderAction> arriveCourierOrder(int id) async {
    current = current!.copyWithStatus('arrived');
    return const CourierOrderAction(id: 1, status: 'arrived');
  }

  @override
  Future<CourierOrderAction> completeCourierOrder(
    int id, {
    required String pin,
  }) async {
    if (pin != validPin) {
      throw const ApiException(
        code: 'invalid_pin',
        message: 'Неверный PIN-код получателя',
        statusCode: 400,
      );
    }
    current = null;
    status = 'online';
    return const CourierOrderAction(id: 1, status: 'delivered');
  }

  @override
  Future<int> sendCourierLocations(List<CourierLocationPoint> points) async {
    sentBatches.add(points);
    return points.length;
  }

  @override
  Future<CourierEarnings> fetchCourierEarnings() async =>
      const CourierEarnings(today: 0, week: 0, total: 0);

  @override
  Future<Paginated<CourierOrder>> fetchCourierHistory({int? page}) async =>
      const Paginated(count: 0, results: []);
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthTokens> refresh(String refreshToken) async =>
      const AuthTokens(access: 'a', refresh: 'r');

  @override
  Future<OtpRequestResult> requestOtp(String phone) => throw UnimplementedError();

  @override
  Future<AuthSession> verifyOtp({required String phone, required String code}) =>
      throw UnimplementedError();

  @override
  Future<User> fetchMe(String accessToken) => throw UnimplementedError();

  @override
  Future<void> logout(String refreshToken) => throw UnimplementedError();
}
