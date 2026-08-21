import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Точка карты в географических координатах.
typedef GeoPoint = ({double lat, double lng});

/// Стилизованная карта трекинга (макет 06-tracking): светло-серый фон,
/// схематичные «кварталы» и «улицы», маршрут пунктиром, маркеры
/// магазина / курьера / дома. Курьер плавно перемещается между апдейтами.
///
/// TODO(native-map): MVP-заглушка вместо настоящей карты. Когда подключим
/// нативные сборки — заменить CustomPainter на 2GIS/Google Maps
/// (google_maps_flutter тянет платформенный код и не заводится на web),
/// публичный интерфейс виджета сохранить.
class TrackingMapWidget extends StatefulWidget {
  const TrackingMapWidget({
    required this.home,
    this.shop,
    this.courier,
    this.shopLabel,
    this.homeLabel,
    this.height = 260,
    super.key,
  });

  /// Координаты магазина (backend пока не отдаёт их клиенту —
  /// тогда маркер магазина и начало маршрута не рисуются).
  final GeoPoint? shop;

  /// Точка доставки (обязательна — без неё карту не показываем).
  final GeoPoint home;

  /// Живая позиция курьера из `courier_location` (может отсутствовать).
  final GeoPoint? courier;

  final String? shopLabel;
  final String? homeLabel;
  final double height;

  @override
  State<TrackingMapWidget> createState() => _TrackingMapWidgetState();
}

class _TrackingMapWidgetState extends State<TrackingMapWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  GeoPoint? _courierFrom;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _courierFrom = widget.courier;
  }

  @override
  void didUpdateWidget(TrackingMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.courier;
    if (next != _courierFrom && next != null) {
      _courierFrom ??= next;
      _controller.forward(from: 0).then((_) => _courierFrom = next);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  GeoPoint? get _animatedCourier {
    final from = _courierFrom;
    final to = widget.courier;
    if (from == null || to == null) return to;
    final t = Curves.easeInOut.transform(_controller.value);
    return (
      lat: from.lat + (to.lat - from.lat) * t,
      lng: from.lng + (to.lng - from.lng) * t,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _TrackingMapPainter(
              shop: widget.shop,
              home: widget.home,
              courier: _animatedCourier,
              shopLabel: widget.shopLabel,
              homeLabel: widget.homeLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingMapPainter extends CustomPainter {
  _TrackingMapPainter({
    required this.home,
    this.shop,
    this.courier,
    this.shopLabel,
    this.homeLabel,
  });

  final GeoPoint? shop;
  final GeoPoint home;
  final GeoPoint? courier;
  final String? shopLabel;
  final String? homeLabel;

  static const _bg = Color(0xFFEDEEF1);
  static const _block = Color(0xFFE2E4E8);

  // Гео → пиксели: вписываем все точки с полями, один масштаб по обеим осям.
  late final List<GeoPoint> _points = [
    home,
    if (shop != null) shop!,
    if (courier != null) courier!,
  ];

  late final double _minLat = _points.map((p) => p.lat).reduce(math.min);
  late final double _maxLat = _points.map((p) => p.lat).reduce(math.max);
  late final double _minLng = _points.map((p) => p.lng).reduce(math.min);
  late final double _maxLng = _points.map((p) => p.lng).reduce(math.max);

  Offset _project(GeoPoint p, Size size) {
    const padding = 46.0;
    // Минимальный охват, чтобы одна точка не растягивалась на весь экран.
    final spanLat = math.max(_maxLat - _minLat, 0.004);
    final spanLng = math.max(_maxLng - _minLng, 0.004);
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    final scale = math.min(w / spanLng, h / spanLat);
    final cx = (_minLng + _maxLng) / 2;
    final cy = (_minLat + _maxLat) / 2;
    return Offset(
      size.width / 2 + (p.lng - cx) * scale,
      size.height / 2 - (p.lat - cy) * scale,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);
    _paintCityBlocks(canvas, size);
    _paintRoute(canvas, size);
    if (shop != null) {
      _paintMarker(
        canvas,
        _project(shop!, size),
        color: AppColors.accent,
        icon: Icons.local_florist,
        label: shopLabel,
      );
    }
    if (courier != null) {
      _paintMarker(
        canvas,
        _project(courier!, size),
        color: AppColors.secondary,
        icon: Icons.moped,
        pulse: true,
      );
    }
    _paintMarker(
      canvas,
      _project(home, size),
      color: AppColors.accent,
      icon: Icons.home,
      label: homeLabel,
      labelBelow: false,
    );
  }

  /// Декоративные «кварталы» и «улицы» — детерминированная сетка,
  /// как на макете (карта схематичная, реальные улицы подставит
  /// нативный провайдер, см. TODO в TrackingMapWidget).
  void _paintCityBlocks(Canvas canvas, Size size) {
    final blockPaint = Paint()..color = _block;
    final streetPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    const stepX = 96.0;
    const stepY = 86.0;
    const gap = 13.0;
    // Улицы — по швам сетки.
    for (var x = stepX / 2; x < size.width; x += stepX) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), streetPaint);
    }
    for (var y = stepY / 2; y < size.height; y += stepY) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), streetPaint);
    }
    // Кварталы между улицами, чуть сплюснутые вариативно.
    var row = 0;
    for (var y = 0.0; y < size.height; y += stepY) {
      var col = 0;
      for (var x = 0.0; x < size.width; x += stepX) {
        final shrink = ((row + col) % 3) * 6.0;
        final rect = Rect.fromLTWH(
          x + gap,
          y + gap + shrink / 2,
          stepX - gap * 2,
          stepY - gap * 2 - shrink,
        );
        if (rect.width > 8 && rect.height > 8) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(6)),
            blockPaint,
          );
        }
        col++;
      }
      row++;
    }
  }

  /// Маршрут пунктиром: магазин → (курьер) → дом.
  void _paintRoute(Canvas canvas, Size size) {
    final waypoints = <GeoPoint>[
      if (shop != null) shop!,
      if (courier != null) courier!,
      home,
    ];
    if (waypoints.length < 2) return;
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i + 1 < waypoints.length; i++) {
      _paintDashedLine(
        canvas,
        _project(waypoints[i], size),
        _project(waypoints[i + 1], size),
        paint,
      );
    }
  }

  void _paintDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 7.0;
    const gap = 6.0;
    final total = (to - from).distance;
    if (total == 0) return;
    final direction = (to - from) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final end = math.min(drawn + dash, total);
      canvas.drawLine(from + direction * drawn, from + direction * end, paint);
      drawn = end + gap;
    }
  }

  void _paintMarker(
    Canvas canvas,
    Offset center, {
    required Color color,
    required IconData icon,
    String? label,
    bool pulse = false,
    bool labelBelow = true,
  }) {
    if (pulse) {
      canvas.drawCircle(
        center,
        22,
        Paint()..color = color.withValues(alpha: 0.25),
      );
    }
    canvas.drawCircle(center, 15, Paint()..color = color);
    canvas.drawCircle(
      center,
      15,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // Глиф Material Icons через TextPainter — надёжнее эмодзи на web.
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 16,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );
    if (label != null && label.isNotEmpty) {
      _paintLabel(canvas, center, label, below: labelBelow);
    }
  }

  void _paintLabel(
    Canvas canvas,
    Offset anchor,
    String text, {
    required bool below,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);
    const padH = 8.0;
    const padV = 3.5;
    final width = textPainter.width + padH * 2;
    final height = textPainter.height + padV * 2;
    final left = math.max(2.0, anchor.dx - width / 2);
    final top = below ? anchor.dy + 20 : anchor.dy - 20 - height;
    final rect = Rect.fromLTWH(left, top, width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = Colors.white,
    );
    textPainter.paint(canvas, Offset(left + padH, top + padV));
  }

  @override
  bool shouldRepaint(_TrackingMapPainter oldDelegate) =>
      oldDelegate.shop != shop ||
      oldDelegate.home != home ||
      oldDelegate.courier != courier ||
      oldDelegate.shopLabel != shopLabel ||
      oldDelegate.homeLabel != homeLabel;
}
