import 'package:flutter/foundation.dart';

import '../api/api_error.dart';
import '../api/models/user.dart';
import 'auth_repository.dart';
import 'token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Auth-gate: unknown → splash, unauthenticated → OTP, authenticated → главная.
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required TokenStorage tokenStorage,
  }) : _repository = repository,
       _tokenStorage = tokenStorage;

  final AuthRepository _repository;
  final TokenStorage _tokenStorage;

  AuthStatus status = AuthStatus.unknown;
  User? user;

  /// Проверка сохранённой сессии при старте приложения.
  Future<void> init() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      user = await _repository.fetchMe(tokens.access);
      await _tokenStorage.save(tokens: tokens, user: user);
      status = AuthStatus.authenticated;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // access протух — пробуем refresh.
        try {
          final fresh = await _repository.refresh(tokens.refresh);
          await _tokenStorage.saveTokens(fresh);
          user = await _repository.fetchMe(fresh.access);
          await _tokenStorage.save(tokens: fresh, user: user);
          status = AuthStatus.authenticated;
        } on ApiException {
          await _tokenStorage.clear();
          status = AuthStatus.unauthenticated;
        }
      } else {
        // Сеть/сервер недоступны — пускаем с локальным профилем,
        // запросы сами уйдут в retry/refresh по 401.
        user = await _tokenStorage.readUser();
        status = user != null
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated;
      }
    }
    notifyListeners();
  }

  /// Возвращает dev_code, если бэкенд в DEBUG его прислал.
  Future<String?> requestOtp(String phone) async {
    final result = await _repository.requestOtp(phone);
    return result.devCode;
  }

  Future<void> verifyOtp({required String phone, required String code}) async {
    final session = await _repository.verifyOtp(phone: phone, code: code);
    await _tokenStorage.save(tokens: session.tokens, user: session.user);
    user = session.user;
    status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> logout() async {
    final refresh = await _tokenStorage.readRefreshToken();
    if (refresh != null) {
      await _repository.logout(refresh);
    }
    await _clearLocal();
  }

  /// Вызывается ApiClient, когда refresh тоже отклонён (сессия мертва).
  Future<void> handleSessionExpired() => _clearLocal();

  Future<void> _clearLocal() async {
    await _tokenStorage.clear();
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
