import 'package:dio/dio.dart';

/// Единый разбор ошибок спеки:
/// `{ "error": { "code": "...", "message": "...", "details": {...} } }`.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Чистый парсер тела ответа об ошибке — отдельно от Dio, чтобы тестировать.
ApiException apiExceptionFromResponse(int? statusCode, Object? data) {
  if (data is Map<String, dynamic>) {
    final error = data['error'];
    if (error is Map<String, dynamic>) {
      return ApiException(
        code: error['code'] as String? ?? 'unknown',
        message: error['message'] as String? ?? 'Неизвестная ошибка',
        statusCode: statusCode,
        details: error['details'] is Map<String, dynamic>
            ? error['details'] as Map<String, dynamic>
            : null,
      );
    }
    // DRF-стиль (otp/request отвечает {"detail": "..."} и при ошибках).
    final detail = data['detail'];
    if (detail is String) {
      return ApiException(
        code: 'error',
        message: detail,
        statusCode: statusCode,
      );
    }
  }
  return ApiException(
    code: 'unknown',
    message: 'Неизвестная ошибка сервера',
    statusCode: statusCode,
  );
}

/// Превращает любое исключение слоя сети в [ApiException].
ApiException parseApiError(Object error) {
  if (error is ApiException) return error;
  if (error is DioException) {
    if (error.response != null) {
      return apiExceptionFromResponse(
        error.response!.statusCode,
        error.response!.data,
      );
    }
    return const ApiException(
      code: 'network',
      message: 'Нет соединения с сервером. Проверьте интернет.',
    );
  }
  return const ApiException(
    code: 'unknown',
    message: 'Что-то пошло не так. Попробуйте ещё раз.',
  );
}
