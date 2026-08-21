import 'package:dio/dio.dart';

import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';
import 'api_error.dart';
import 'config.dart';
import 'models/courier.dart';
import 'models/order.dart';
import 'models/product.dart';
import 'models/shop.dart';
import 'pagination.dart';

String? resolveMediaUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return path;
  return '$kMediaBaseUrl$path';
}

/// Dio-клиент с Bearer access-токеном, авто-refresh по 401
/// и единым разбором ошибок спеки.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    required AuthRepository authRepository,
    void Function()? onSessionExpired,
    String baseUrl = kApiBaseUrl,
  })  : _tokenStorage = tokenStorage,
        _authRepository = authRepository,
        _onSessionExpired = onSessionExpired,
        dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final TokenStorage _tokenStorage;
  final AuthRepository _authRepository;
  final void Function()? _onSessionExpired;

  final Dio dio;

  /// Дедупликация параллельных refresh-запросов.
  Future<AuthTokens>? _refreshFuture;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.access}';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final isRefreshCall = error.requestOptions.path.contains('/auth/');
    final alreadyRetried = error.requestOptions.extra['retried'] == true;
    if (error.response?.statusCode != 401 || isRefreshCall || alreadyRetried) {
      handler.next(error);
      return;
    }
    try {
      final tokens = await (_refreshFuture ??= _doRefresh());
      final options = error.requestOptions
        ..headers['Authorization'] = 'Bearer ${tokens.access}'
        ..extra['retried'] = true;
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } on ApiException {
      // Refresh отклонён — сессия мертва, разлогиниваем.
      _onSessionExpired?.call();
      handler.next(error);
    }
  }

  Future<AuthTokens> _doRefresh() async {
    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken == null) {
        throw const ApiException(code: 'no_refresh', message: 'Нет сессии');
      }
      final tokens = await _authRepository.refresh(refreshToken);
      await _tokenStorage.saveTokens(tokens);
      return tokens;
    } finally {
      _refreshFuture = null;
    }
  }

  // ---------------- Каталог (§2 спеки) ----------------

  Future<Paginated<Shop>> fetchShops({
    double lat = 38.5598,
    double lng = 68.7870,
    bool openNow = false,
    String? query,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/shops/',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          if (openNow) 'open_now': 1,
          if (query != null && query.isNotEmpty) 'q': query,
        },
      );
      return Paginated.fromJson(response.data!, Shop.fromJson);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  Future<Shop> fetchShop(int id) async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/shops/$id/');
      return Shop.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  Future<Paginated<Product>> fetchProducts({
    int? shopId,
    int? categoryId,
    bool featured = false,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/products/',
        queryParameters: {
          if (shopId != null) 'shop_id': shopId,
          if (categoryId != null) 'category': categoryId,
          if (featured) 'featured': 1,
        },
      );
      return Paginated.fromJson(response.data!, Product.fromJson);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /products/{id}/` — карточка товара: описание и все фото,
  /// которых нет в списках.
  Future<Product> fetchProduct(int id) async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/products/$id/');
      return Product.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /banners/` — простой список без пагинации.
  Future<List<PromoBanner>> fetchBanners() async {
    try {
      final response = await dio.get<List<dynamic>>('/banners/');
      return response.data!
          .whereType<Map<String, dynamic>>()
          .map(PromoBanner.fromJson)
          .toList();
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /categories/` — простой список без пагинации.
  Future<List<Category>> fetchCategories() async {
    try {
      final response = await dio.get<List<dynamic>>('/categories/');
      return response.data!
          .whereType<Map<String, dynamic>>()
          .map(Category.fromJson)
          .toList();
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  // ---------------- Заказы и оплата (§3–§4 спеки) ----------------

  /// `POST /orders/` — создание заказа. Тело собирает экран оформления,
  /// заголовок `Idempotency-Key` обязателен для защиты от повторных тапов.
  Future<CreatedOrder> createOrder({
    required Map<String, dynamic> body,
    required String idempotencyKey,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/orders/',
        data: body,
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return CreatedOrder.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `POST /orders/{id}/pay/` — инициализация оплаты (пока provider "stub").
  Future<PaymentResult> payOrder({
    required int orderId,
    required String idempotencyKey,
    String provider = 'stub',
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/orders/$orderId/pay/',
        data: {'provider': provider},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return PaymentResult.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /orders/` — мои заказы; `filter`: `active` или `history`.
  Future<Paginated<OrderSummary>> fetchOrders({String? filter}) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/orders/',
        queryParameters: {if (filter != null) 'status': filter},
      );
      return Paginated.fromJson(response.data!, OrderSummary.fromJson);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /orders/{id}/` — детали заказа.
  Future<OrderDetail> fetchOrder(int id) async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/orders/$id/');
      return OrderDetail.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `POST /orders/{id}/cancel/` — отмена клиентом.
  /// Правила возврата (api.md §3): до accepted — полный, после — минус удержание.
  Future<void> cancelOrder(int id, {String reason = ''}) async {
    try {
      await dio.post<void>('/orders/$id/cancel/', data: {'reason': reason});
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `POST /orders/{id}/photo/respond/` — реакция на фото букета (api.md §5).
  Future<void> respondOrderPhoto(int id, {required bool approved}) async {
    try {
      await dio.post<void>(
        '/orders/$id/photo/respond/',
        data: {'approved': approved},
      );
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  // ---------------- Курьер (§6 спеки) ----------------

  /// `PATCH /courier/status/` — выход/уход с линии.
  /// Возвращает фактический статус профиля: online / offline / busy
  /// (busy — система выставляет при активном заказе).
  Future<String> setCourierStatus(String status) async {
    try {
      final response = await dio.patch<Map<String, dynamic>>(
        '/courier/status/',
        data: {'status': status},
      );
      return response.data!['status'] as String;
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /courier/orders/current/` — активный заказ или null.
  Future<CourierOrder?> fetchCourierCurrentOrder() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/courier/orders/current/',
      );
      final order = response.data!['order'];
      return order is Map<String, dynamic> ? CourierOrder.fromJson(order) : null;
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /courier/orders/available/` — заказы ready без курьера
  /// (простой список, без пагинации).
  Future<List<CourierOrder>> fetchCourierAvailableOrders() async {
    try {
      final response = await dio.get<List<dynamic>>(
        '/courier/orders/available/',
      );
      return response.data!
          .whereType<Map<String, dynamic>>()
          .map(CourierOrder.fromJson)
          .toList();
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `POST /courier/orders/{id}/accept/` — взять заказ.
  /// Гонка курьеров: 409 order_taken, если заказ уже забрали.
  Future<CourierOrderAction> acceptCourierOrder(int id) =>
      _courierOrderAction(id, 'accept');

  /// `POST /courier/orders/{id}/pickup/` — забрал у магазина → on_the_way.
  Future<CourierOrderAction> pickupCourierOrder(int id) =>
      _courierOrderAction(id, 'pickup');

  /// `POST /courier/orders/{id}/arrive/` — на месте → arrived.
  Future<CourierOrderAction> arriveCourierOrder(int id) =>
      _courierOrderAction(id, 'arrive');

  Future<CourierOrderAction> _courierOrderAction(int id, String action) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/courier/orders/$id/$action/',
      );
      return CourierOrderAction.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `POST /courier/orders/{id}/complete/` — завершение по PIN получателя.
  /// Неверный PIN — 400 invalid_pin.
  Future<CourierOrderAction> completeCourierOrder(
    int id, {
    required String pin,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/courier/orders/$id/complete/',
        data: {'pin': pin},
      );
      return CourierOrderAction.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `POST /courier/location/` — батч GPS-точек. Возвращает,
  /// сколько точек принято (`accepted`); 409 no_active_delivery вне доставки.
  Future<int> sendCourierLocations(List<CourierLocationPoint> points) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/courier/location/',
        data: {'points': points.map((p) => p.toJson()).toList()},
      );
      return response.data!['accepted'] as int? ?? 0;
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /courier/earnings/` — заработок: сегодня / неделя / всего.
  Future<CourierEarnings> fetchCourierEarnings() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/courier/earnings/',
      );
      return CourierEarnings.fromJson(response.data!);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }

  /// `GET /courier/orders/history/` — завершённые доставки (пагинация).
  Future<Paginated<CourierOrder>> fetchCourierHistory({int? page}) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/courier/orders/history/',
        queryParameters: {if (page != null) 'page': page},
      );
      return Paginated.fromJson(response.data!, CourierOrder.fromJson);
    } on DioException catch (e) {
      throw parseApiError(e);
    }
  }
}
