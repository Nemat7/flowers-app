import 'package:dio/dio.dart';
import 'package:flowers_client/src/api/api_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('apiExceptionFromResponse', () {
    test('разбирает ошибку спеки {error:{code,message,details}}', () {
      final e = apiExceptionFromResponse(409, {
        'error': {
          'code': 'shop_closed',
          'message': 'Магазин закрыт',
          'details': {'opens_at': '09:00'},
        },
      });
      expect(e.code, 'shop_closed');
      expect(e.message, 'Магазин закрыт');
      expect(e.statusCode, 409);
      expect(e.details, {'opens_at': '09:00'});
    });

    test('разбирает DRF-стиль {detail: ...}', () {
      final e = apiExceptionFromResponse(429, {'detail': 'Слишком часто'});
      expect(e.message, 'Слишком часто');
      expect(e.statusCode, 429);
    });

    test('непонятное тело → unknown', () {
      final e = apiExceptionFromResponse(500, '<html>oops</html>');
      expect(e.code, 'unknown');
      expect(e.statusCode, 500);
    });
  });

  group('parseApiError', () {
    test('DioException с ответом → тело спеки', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/shops/'),
        response: Response(
          requestOptions: RequestOptions(path: '/shops/'),
          statusCode: 401,
          data: {
            'error': {'code': 'unauthorized', 'message': 'Нужен вход'},
          },
        ),
      );
      final e = parseApiError(dioError);
      expect(e.code, 'unauthorized');
      expect(e.statusCode, 401);
    });

    test('DioException без ответа → network', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/shops/'),
        type: DioExceptionType.connectionError,
      );
      expect(parseApiError(dioError).code, 'network');
    });

    test('ApiException возвращается как есть', () {
      const e = ApiException(code: 'x', message: 'y');
      expect(identical(parseApiError(e), e), isTrue);
    });
  });
}
