import 'package:dio/dio.dart';

import '../api/api_error.dart';
import '../api/config.dart';
import '../api/models/user.dart';
import 'token_storage.dart';


class AuthSession {
  const AuthSession({required this.tokens, required this.user});

  final AuthTokens tokens;
  final User user;
}

class OtpRequestResult {
  const OtpRequestResult({this.devCode});

  /// Возвращается бэкендом только в DEBUG — для автологина в разработке.
  final String? devCode;
}

/// OTP-flow и токены. Свой Dio без auth-интерцептора —
/// сюда Bearer не нужен (кроме fetchMe).
abstract class AuthRepository {
  Future<OtpRequestResult> requestOtp(String phone);
  Future<AuthSession> verifyOtp({required String phone, required String code});
  Future<AuthTokens> refresh(String refreshToken);
  Future<User> fetchMe(String accessToken);
  Future<void> logout(String refreshToken);
}

class DioAuthRepository implements AuthRepository {
  DioAuthRepository({String baseUrl = kApiBaseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

  final Dio _dio;

  @override
  Future<OtpRequestResult> requestOtp(String phone) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/otp/request/',
        data: {'phone': phone},
      );
      return OtpRequestResult(
        devCode: response.data?['dev_code'] as String?,
      );
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  @override
  Future<AuthSession> verifyOtp({
    required String phone,
    required String code,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/otp/verify/',
        data: {'phone': phone, 'code': code},
      );
      final data = response.data!;
      return AuthSession(
        tokens: AuthTokens(
          access: data['access'] as String,
          refresh: data['refresh'] as String,
        ),
        user: User.fromJson(data['user'] as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh/',
        data: {'refresh': refreshToken},
      );
      final data = response.data!;
      return AuthTokens(
        access: data['access'] as String,
        refresh: data['refresh'] as String,
      );
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  @override
  Future<User> fetchMe(String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/users/me/',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return User.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  @override
  Future<void> logout(String refreshToken) async {
    try {
      await _dio.post<void>('/auth/logout/', data: {'refresh': refreshToken});
    } on DioException {
      // Инвалидация на сервере best-effort: локально разлогиним в любом случае.
    }
  }
}
