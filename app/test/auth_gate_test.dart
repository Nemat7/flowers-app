import 'package:flowers_client/src/api/api_client.dart';
import 'package:flowers_client/src/api/api_error.dart';
import 'package:flowers_client/src/api/models/user.dart';
import 'package:flowers_client/src/app/auth_gate.dart';
import 'package:flowers_client/src/auth/auth_controller.dart';
import 'package:flowers_client/src/auth/auth_repository.dart';
import 'package:flowers_client/src/auth/screens/phone_screen.dart';
import 'package:flowers_client/src/auth/token_storage.dart';
import 'package:flowers_client/src/cart/cart_controller.dart';
import 'package:flowers_client/src/home/home_screen.dart';
import 'package:flowers_client/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.me, this.failRefresh = false});

  final User? me;
  final bool failRefresh;

  @override
  Future<OtpRequestResult> requestOtp(String phone) async =>
      const OtpRequestResult(devCode: '123456');

  @override
  Future<AuthSession> verifyOtp({
    required String phone,
    required String code,
  }) async =>
      AuthSession(
        tokens: const AuthTokens(access: 'a', refresh: 'r'),
        user: me ?? const User(id: 1, phone: '+992900000001', role: 'client'),
      );

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    if (failRefresh) {
      throw const ApiException(
        code: 'token_invalid',
        message: 'refresh недействителен',
        statusCode: 401,
      );
    }
    return const AuthTokens(access: 'a2', refresh: 'r2');
  }

  @override
  Future<User> fetchMe(String accessToken) async {
    final user = me;
    if (user == null) {
      throw const ApiException(
        code: 'unauthorized',
        message: 'Нужен вход',
        statusCode: 401,
      );
    }
    return user;
  }

  @override
  Future<void> logout(String refreshToken) async {}
}

Widget _buildApp(AuthController controller) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthController>.value(value: controller),
      Provider<ApiClient>(
        create: (_) => ApiClient(
          tokenStorage: TokenStorage(),
          authRepository: FakeAuthRepository(),
        ),
      ),
      ChangeNotifierProvider<CartController>(
        create: (_) => CartController(),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const AuthGate()),
  );
}

void main() {
  testWidgets('без сохранённых токенов показывает экран телефона',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = AuthController(
      repository: FakeAuthRepository(),
      tokenStorage: TokenStorage(),
    );
    await controller.init();

    await tester.pumpWidget(_buildApp(controller));
    await tester.pump();
    // Сплеш держится минимум 1.2 c — проматываем.
    await tester.pump(const Duration(milliseconds: 1300));

    expect(find.byType(PhoneScreen), findsOneWidget);
    expect(find.text('Вход по номеру телефона'), findsOneWidget);
  });

  testWidgets('валидная сессия ведёт на главную', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.access': 'a',
      'auth.refresh': 'r',
    });
    final controller = AuthController(
      repository: FakeAuthRepository(
        me: const User(
          id: 1,
          phone: '+992900000001',
          role: 'client',
          name: 'Тест',
        ),
      ),
      tokenStorage: TokenStorage(),
    );
    await controller.init();

    await tester.pumpWidget(_buildApp(controller));
    await tester.pump();
    // Даём Dio завершить запрос /shops/ (в тесте HTTP замокан → быстрый 400,
    // показываем состояние ошибки) и отпустить таймауты.
    await tester.pump(const Duration(seconds: 20));
    // Запрос стартует только после сплеша (1.2 c) — добиваем хвостовые
    // нулевые таймеры Dio ещё одной секундой фейкового времени.
    await tester.pump(const Duration(seconds: 1));

    expect(controller.status, AuthStatus.authenticated);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('ул. Рудаки 25'), findsOneWidget);
  });

  testWidgets('мёртвый refresh разлогинивает', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.access': 'a',
      'auth.refresh': 'r',
    });
    final controller = AuthController(
      repository: FakeAuthRepository(failRefresh: true),
      tokenStorage: TokenStorage(),
    );
    await controller.init();

    await tester.pumpWidget(_buildApp(controller));
    await tester.pump();
    // Сплеш держится минимум 1.2 c — проматываем.
    await tester.pump(const Duration(milliseconds: 1300));

    expect(controller.status, AuthStatus.unauthenticated);
    expect(find.byType(PhoneScreen), findsOneWidget);
  });
}
