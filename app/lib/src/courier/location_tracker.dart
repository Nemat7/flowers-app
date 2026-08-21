import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../api/models/courier.dart';

/// Поток позиций из geolocator (web: запросит разрешение в браузере).
/// Бросает [LocationPermissionDeniedException], если разрешение не дано.
Stream<CourierLocationPoint> geolocatorPositionStream() async* {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw LocationPermissionDeniedException();
  }
  const settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );
  await for (final position in Geolocator.getPositionStream(
    locationSettings: settings,
  )) {
    yield CourierLocationPoint(
      lat: position.latitude,
      lng: position.longitude,
      ts: DateTime.now().millisecondsSinceEpoch / 1000,
    );
  }
}

/// Разрешение на геолокацию не дано — трекинг не стартует,
/// но шаги заказа не блокируются.
class LocationPermissionDeniedException implements Exception {
  @override
  String toString() => 'LocationPermissionDeniedException';
}

/// Источник позиций (geolocator в приложении, мок в тестах).
typedef PositionStreamFactory = Stream<CourierLocationPoint> Function();

/// Отправка батча точек на backend (`POST /courier/location/`).
typedef LocationBatchSender = Future<void> Function(
  List<CourierLocationPoint> points,
);

/// GPS-трекинг активной доставки: буферит позиции и шлёт батчем каждые
/// [flushInterval] (api.md §6 — каждые 10–15 сек, не более 100 точек).
///
/// Ошибка отправки не роняет трекер: неотправленные точки возвращаются
/// в буфер (с обрезкой до [maxBatch] — самые старые выбрасываются), о
/// проблеме сообщаем через [onError]. Остановка — [stop] (после complete
/// или dispose экрана).
class LocationTracker {
  LocationTracker({
    required PositionStreamFactory positionStream,
    required LocationBatchSender send,
    this.flushInterval = const Duration(seconds: 10),
    this.maxBatch = 100,
    this.onError,
  })  : _positionStream = positionStream,
        _send = send;

  final PositionStreamFactory _positionStream;
  final LocationBatchSender _send;

  /// Период отправки батча на backend.
  final Duration flushInterval;

  /// Верхний предел буфера (backend принимает максимум 100 точек за раз).
  final int maxBatch;

  /// Ошибки источника позиций (нет разрешения и т.п.) и отправки.
  final void Function(Object error)? onError;

  final _buffer = <CourierLocationPoint>[];
  StreamSubscription<CourierLocationPoint>? _subscription;
  Timer? _flushTimer;
  bool _running = false;
  bool _flushing = false;

  bool get isRunning => _running;

  /// Сколько точек сейчас в буфере (для тестов/диагностики).
  int get bufferedCount => _buffer.length;

  void start() {
    if (_running) return;
    _running = true;
    try {
      _subscription = _positionStream().listen(
        _buffer.add,
        onError: (Object error) => onError?.call(error),
      );
    } catch (error) {
      onError?.call(error);
    }
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());
  }

  /// Отправить накопленное, если буфер не пуст.
  Future<void> flush() async {
    if (_flushing || _buffer.isEmpty) return;
    _flushing = true;
    final batch = List<CourierLocationPoint>.of(_buffer);
    _buffer.clear();
    try {
      await _send(batch);
    } catch (error) {
      // Сеть мигнула или доставка завершилась — вернём точки в буфер
      // (старые выбрасываем, чтобы не раздувать батч сверх maxBatch).
      _buffer.insertAll(0, batch);
      if (_buffer.length > maxBatch) {
        _buffer.removeRange(0, _buffer.length - maxBatch);
      }
      onError?.call(error);
    } finally {
      _flushing = false;
    }
  }

  /// Остановить трекинг: отписаться от геолокации и отправить остаток.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await flush();
  }
}
