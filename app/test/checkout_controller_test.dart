import 'package:flowers_client/src/api/api_client.dart';
import 'package:flowers_client/src/auth/auth_repository.dart';
import 'package:flowers_client/src/auth/token_storage.dart';
import 'package:flowers_client/src/checkout/checkout_controller.dart';
import 'package:flutter_test/flutter_test.dart';

CheckoutController _controller(String Function() idGenerator) =>
    CheckoutController(
      // ApiClient конструируется без сети — submit() в тестах не вызываем.
      apiClient: ApiClient(
        tokenStorage: TokenStorage(),
        authRepository: DioAuthRepository(),
      ),
      idGenerator: idGenerator,
    );

void main() {
  group('CheckoutController: Idempotency-Key', () {
    test('ключ генерируется один раз и стабилен между вызовами', () {
      var calls = 0;
      final controller = _controller(() => 'uuid-${++calls}');

      final first = controller.idempotencyKey;
      final second = controller.idempotencyKey;
      final third = controller.idempotencyKey;

      expect(first, 'uuid-1');
      expect(second, first);
      expect(third, first);
      expect(calls, 1, reason: 'генератор вызывается ровно один раз');
    });

    test('renewIdempotencyKey начинает новую попытку с новым ключом', () {
      var calls = 0;
      final controller = _controller(() => 'uuid-${++calls}');

      final first = controller.idempotencyKey;
      controller.renewIdempotencyKey();
      final second = controller.idempotencyKey;

      expect(first, isNot(second));
      expect(second, 'uuid-2');
      // И дальше снова стабилен (повторный тап «Оплатить» — тот же ключ).
      expect(controller.idempotencyKey, second);
      expect(calls, 2);
    });

    test('ключ по умолчанию — валидный uuid v4', () {
      final controller = CheckoutController(
        apiClient: ApiClient(
          tokenStorage: TokenStorage(),
          authRepository: DioAuthRepository(),
        ),
      );
      final key = controller.idempotencyKey;
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(key),
        isTrue,
      );
      // Сервер требует UUID (orders/views.py): не-UUID даст 400.
    });
  });
}
