import 'dart:async';

import 'package:flowers_client/src/api/models/courier.dart';
import 'package:flowers_client/src/courier/location_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<CourierLocationPoint> positions;

  CourierLocationPoint point(int i) =>
      CourierLocationPoint(lat: 38.56 + i * 0.001, lng: 68.78, ts: 1754800000 + i * 10);

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('условие не наступило за 3 секунды');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  setUp(() {
    positions = StreamController<CourierLocationPoint>.broadcast();
  });

  tearDown(() async {
    await positions.close();
  });

  test('точки буферятся и уходят батчем по таймеру', () async {
    final batches = <List<CourierLocationPoint>>[];
    final tracker = LocationTracker(
      positionStream: () => positions.stream,
      send: (points) async => batches.add(points),
      flushInterval: const Duration(milliseconds: 20),
    );
    tracker.start();
    addTearDown(tracker.stop);

    positions.add(point(0));
    positions.add(point(1));
    await waitFor(() => batches.isNotEmpty);

    expect(batches.first, hasLength(2));
    expect(tracker.bufferedCount, 0);
    // Пустой буфер не шлёт лишних запросов.
    final sent = batches.length;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(batches.length, sent);
  });

  test('ошибка отправки: точки возвращаются в буфер, onError вызван, '
      'следующий тик шлёт снова', () async {
    final batches = <List<CourierLocationPoint>>[];
    final errors = <Object>[];
    var fail = true;
    final tracker = LocationTracker(
      positionStream: () => positions.stream,
      send: (points) async {
        if (fail) throw Exception('сеть мигнула');
        batches.add(points);
      },
      flushInterval: const Duration(milliseconds: 20),
      onError: errors.add,
    );
    tracker.start();
    addTearDown(tracker.stop);

    positions.add(point(0));
    await waitFor(() => errors.isNotEmpty);
    expect(tracker.bufferedCount, 1);

    fail = false;
    await waitFor(() => batches.isNotEmpty);
    expect(batches.first, hasLength(1));
  });

  test('буфер обрезается до maxBatch — старые точки выбрасываются', () async {
    final errors = <Object>[];
    final tracker = LocationTracker(
      positionStream: () => positions.stream,
      send: (points) async => throw Exception('offline'),
      flushInterval: const Duration(milliseconds: 10),
      maxBatch: 5,
      onError: errors.add,
    );
    tracker.start();
    addTearDown(tracker.stop);

    for (var i = 0; i < 8; i++) {
      positions.add(point(i));
    }
    await waitFor(() => errors.isNotEmpty);
    await waitFor(() => tracker.bufferedCount == 5);
  });

  test('stop() отправляет остаток буфера и останавливает таймер', () async {
    final batches = <List<CourierLocationPoint>>[];
    final tracker = LocationTracker(
      positionStream: () => positions.stream,
      send: (points) async => batches.add(points),
      flushInterval: const Duration(minutes: 5), // таймер не успеет
    );
    tracker.start();

    positions.add(point(0));
    // Дать listen() обработать событие.
    await waitFor(() => tracker.bufferedCount == 1);

    await tracker.stop();

    expect(tracker.isRunning, isFalse);
    expect(batches, hasLength(1));
    expect(batches.single, hasLength(1));
  });

  test('нет разрешения на геолокацию: onError, трекер остаётся живым',
      () async {
    final errors = <Object>[];
    final tracker = LocationTracker(
      positionStream: () => Stream.error(LocationPermissionDeniedException()),
      send: (points) async {},
      flushInterval: const Duration(milliseconds: 20),
      onError: errors.add,
    );
    tracker.start();
    addTearDown(tracker.stop);

    await waitFor(() => errors.isNotEmpty);
    expect(errors.first, isA<LocationPermissionDeniedException>());
    expect(tracker.isRunning, isTrue);
  });
}
