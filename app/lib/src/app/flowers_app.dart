import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';
import '../cart/cart_controller.dart';
import '../theme/theme.dart';
import 'auth_gate.dart';

/// Корневой виджет: провайдеры + MaterialApp + AuthGate.
class FlowersApp extends StatelessWidget {
  const FlowersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<TokenStorage>(create: (_) => TokenStorage()),
        Provider<AuthRepository>(create: (_) => DioAuthRepository()),
        ChangeNotifierProvider<AuthController>(
          create: (context) => AuthController(
            repository: context.read<AuthRepository>(),
            tokenStorage: context.read<TokenStorage>(),
          )..init(),
        ),
        ProxyProvider3<TokenStorage, AuthRepository, AuthController, ApiClient>(
          update: (context, tokenStorage, authRepository, auth, _) => ApiClient(
            tokenStorage: tokenStorage,
            authRepository: authRepository,
            onSessionExpired: auth.handleSessionExpired,
          ),
        ),
        ChangeNotifierProvider<CartController>(
          create: (_) => CartController(),
        ),
      ],
      child: MaterialApp(
        title: 'Цветы Душанбе',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}
