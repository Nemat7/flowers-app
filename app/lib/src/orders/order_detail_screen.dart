import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/order.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';
import 'orders_screen.dart' show formatOrderDate, orderStatusColors;
import 'tracking_map.dart';
import 'tracking_service.dart';

/// Детали заказа (GET /orders/{id}/): статус-блок с LIVE-бейджем,
/// стилизованная карта трекинга (WS /ws/client/orders/{id}/, api.md §7),
/// таймлайн статусов, карточка курьера, PIN доставки.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final int orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderDetail? _order;
  String? _error;

  OrderTrackingService? _tracking;
  StreamSubscription<OrderTrackingEvent>? _trackingSub;
  bool _live = false;
  GeoPoint? _courierPosition;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    unawaited(_trackingSub?.cancel());
    unawaited(_tracking?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final order = await context.read<ApiClient>().fetchOrder(widget.orderId);
      if (!mounted) return;
      setState(() => _order = order);
      _startTracking(order);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  /// Тихое обновление (по WS/polling-событию) — без спиннера и ошибок на экране.
  Future<void> _refresh() async {
    try {
      final order = await context.read<ApiClient>().fetchOrder(widget.orderId);
      if (!mounted) return;
      setState(() => _order = order);
      if (orderStatusIsFinal(order.status)) _stopTracking();
    } on ApiException {
      // Следующее событие / pull-to-refresh попробует снова.
    }
  }

  void _startTracking(OrderDetail order) {
    if (_tracking != null || orderStatusIsFinal(order.status)) return;
    final api = context.read<ApiClient>();
    final service = OrderTrackingService(
      orderId: widget.orderId,
      tokenStorage: context.read(),
      authRepository: context.read(),
      initialStatus: order.status,
      pollStatus: () async => (await api.fetchOrder(widget.orderId)).status,
    );
    _tracking = service;
    _trackingSub = service.events.listen(_onTrackingEvent);
    service.start();
  }

  void _stopTracking() {
    unawaited(_trackingSub?.cancel());
    unawaited(_tracking?.dispose());
    _trackingSub = null;
    _tracking = null;
    if (mounted) setState(() => _live = false);
  }

  void _onTrackingEvent(OrderTrackingEvent event) {
    switch (event) {
      case TrackingStatusChanged():
        // Дотягиваем детали целиком — нужна полная история для таймлайна.
        _refresh();
      case TrackingBouquetPhoto():
        // Магазин прислал фото букета — тихо обновляем детали.
        _refresh();
      case TrackingCourierLocation():
        setState(() => _courierPosition = (lat: event.lat, lng: event.lng));
      case TrackingConnectionChanged():
        setState(() => _live = event.isLive);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(
        title: Text(order == null ? 'Заказ' : 'Заказ ${order.number}'),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off,
                      size: 48, color: AppColors.textHint),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _load,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(160, 44),
                    ),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            )
          : order == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                )
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    children: [
                      _buildStatusCard(order),
                      if (order.bouquetPhoto != null &&
                          !orderStatusIsFinal(order.status))
                        _buildBouquetPhotoCard(order),
                      if (_showMap(order)) _buildMap(order),
                      if (order.courier != null) _buildCourierCard(order),
                      if (order.deliveryPin != null) _buildPinCard(order),
                      _buildTimelineCard(order),
                      _buildItemsCard(order),
                      _buildInfoCard(order),
                      _buildTotalsCard(order),
                      if (_canCancel(order.status)) _buildCancelButton(order),
                    ],
                  ),
                ),
    );
  }

  Widget _card({required Widget child, String? label}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }

  /// Статус-блок по макету 06: крупный заголовок, пояснение и LIVE-бейдж,
  /// когда заказ в picked_up..arrived и WS-канал жив.
  Widget _buildStatusCard(OrderDetail order) {
    final (fg, bg) = orderStatusColors(order.status);
    final description = orderStatusDescription(order.status);
    final showLive = _live && orderStatusIsTrackable(order.status);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  orderStatusHeadline(order.status),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (showLive) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LiveDot(),
                      SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    orderStatusLabel(order.status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 3),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${order.shopName} · ${formatOrderDate(order.createdAt)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  // --- Фото букета от магазина (api.md §5) ---

  bool _photoResponding = false;

  /// Карточка «Фото вашего букета»: фото на всю ширину + одобрение.
  /// До ответа — две кнопки; после — только статус решения.
  Widget _buildBouquetPhotoCard(OrderDetail order) {
    final photo = order.bouquetPhoto!;
    return _card(
      label: 'Фото вашего букета',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              photo.url,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                height: 120,
                color: AppColors.fill,
                alignment: Alignment.center,
                child: const Text(
                  'Не удалось загрузить фото',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (photo.awaitingResponse) ...[
            const Text(
              'Магазин собрал букет — проверьте фото до отправки курьера',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _photoResponding
                        ? null
                        : () => _respondPhoto(order, approved: true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.textHint,
                    ),
                    child: const Text('Всё отлично'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _photoResponding
                        ? null
                        : () => _respondPhoto(order, approved: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.fill,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                    ),
                    child: const Text('Есть проблема'),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              photo.approved!
                  ? 'Вы подтвердили фото — букет скоро отправят'
                  : 'Вы сообщили о проблеме — магазин переделает букет',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: photo.approved!
                    ? AppColors.secondary
                    : AppColors.error,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _respondPhoto(OrderDetail order, {required bool approved}) async {
    setState(() => _photoResponding = true);
    try {
      await context
          .read<ApiClient>()
          .respondOrderPhoto(widget.orderId, approved: approved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'Спасибо! Магазин получил подтверждение'
                : 'Сообщили магазину — букет переделают',
          ),
        ),
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _photoResponding = false);
    }
  }

  /// Карту показываем, пока заказ активен и известна точка доставки.
  bool _showMap(OrderDetail order) {
    final address = order.address;
    return address?.lat != null &&
        address?.lng != null &&
        !orderStatusIsFinal(order.status) &&
        order.status != 'created' &&
        order.status != 'payment_failed';
  }

  // --- Отмена заказа (business-logic.md §7) ---

  bool _cancelling = false;

  /// Отменить можно, пока курьер не забрал заказ у магазина.
  static const _cancellableStatuses = {
    'paid', 'shop_pending', 'accepted', 'preparing', 'ready', 'courier_assigned',
  };

  /// Точное удержание по этапу заказа (docs/refund-policy.md):
  /// accepted/preparing → 10%, ready/courier_assigned → 20%, раньше — без удержания.
  static int? _retentionPercent(String status) => switch (status) {
        'accepted' || 'preparing' => 10,
        'ready' || 'courier_assigned' => 20,
        _ => null,
      };

  bool _canCancel(String status) => _cancellableStatuses.contains(status);

  Widget _buildCancelButton(OrderDetail order) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Center(
        child: TextButton(
          onPressed: _cancelling ? null : () => _confirmCancel(order),
          child: _cancelling
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'Отменить заказ',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(OrderDetail order) async {
    final retention = _retentionPercent(order.status);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: Text(
          switch (retention) {
            10 =>
              'Магазин уже начал собирать заказ — вернём сумму за вычетом удержания 10%. Остальное вернётся на кошелёк.',
            20 =>
              'Букет уже собран — вернём сумму за вычетом удержания 20%. Остальное вернётся на кошелёк.',
            _ => 'Вернём всю сумму на кошелёк полностью.',
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Не отменять'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Отменить заказ',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await context.read<ApiClient>().cancelOrder(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заказ отменён, деньги возвращены')),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Widget _buildMap(OrderDetail order) {
    final address = order.address!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TrackingMapWidget(
        home: (lat: address.lat!, lng: address.lng!),
        courier: _courierPosition,
        homeLabel: address.addressText,
      ),
    );
  }

  /// Карточка курьера по макету 06. Backend пока не отдаёт `courier`
  /// в деталях заказа — блок скрыт; появится сам, когда поле появится.
  Widget _buildCourierCard(OrderDetail order) {
    final courier = order.courier!;
    return _card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: AppColors.successSurface,
            child: Text(
              courier.name.isNotEmpty ? courier.name[0].toUpperCase() : '—',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courier.name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Курьер',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (courier.phone != null && courier.phone!.isNotEmpty)
            IconButton.filled(
              onPressed: () => launchUrl(
                Uri(scheme: 'tel', path: courier.phone),
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.call),
              tooltip: 'Позвонить курьеру',
            ),
        ],
      ),
    );
  }

  /// PIN по макету 06: каждая цифра в своём «квадратике».
  Widget _buildPinCard(OrderDetail order) {
    final digits = order.deliveryPin!.split('');
    return _card(
      label: 'PIN получателя',
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Сообщите код курьеру при вручении',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 10),
          for (final digit in digits)
            Container(
              width: 30,
              height: 36,
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                color: AppColors.fill,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                digit,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Вертикальный таймлайн статусов. Backend отдаёт историю от новых
  /// к старым — разворачиваем в хронологию. Обновляется по status_changed
  /// через тихий refetch деталей заказа.
  Widget _buildTimelineCard(OrderDetail order) {
    final history = order.statusHistory.reversed.toList();
    if (history.isEmpty) return const SizedBox.shrink();
    return _card(
      label: 'Статусы заказа',
      child: Column(
        children: [
          for (var i = 0; i < history.length; i++)
            _timelineRow(
              entry: history[i],
              isFirst: i == 0,
              isLast: i == history.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _timelineRow({
    required OrderStatusEntry entry,
    required bool isFirst,
    required bool isLast,
  }) {
    const activeColor = AppColors.textPrimary;
    const doneColor = AppColors.accent;
    final color = isLast ? activeColor : doneColor;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: isLast ? color : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 3),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: const Color(0xFFECECEF),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    orderStatusLabel(entry.status),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (entry.comment != null && entry.comment!.isNotEmpty)
                    Text(
                      entry.comment!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  Text(
                    formatOrderDate(entry.at),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(OrderDetail order) {
    return _card(
      label: 'Состав заказа',
      child: Column(
        children: [
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.productName} × ${item.qty}',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  Text(
                    formatSomoni(item.lineTotal),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(OrderDetail order) {
    final rows = <(String, String)>[
      if (order.address != null) ('Адрес', order.address!.addressText),
      if (order.address?.details?.isNotEmpty == true)
        ('Детали', order.address!.details!),
      ('Получатель', '${order.recipientName}, ${order.recipientPhone}'),
      if (order.slotType == 'scheduled' && order.scheduledAt != null)
        ('Ко времени', formatOrderDate(order.scheduledAt)),
      if (order.isAnonymous) ('Доставка', 'анонимная'),
      if (order.cardText.isNotEmpty) ('Открытка', '«${order.cardText}»'),
      if (order.comment.isNotEmpty) ('Комментарий', order.comment),
      if (order.cancelReason != null && order.cancelReason!.isNotEmpty)
        ('Причина отмены', order.cancelReason!),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return _card(
      label: 'Детали',
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(value, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalsCard(OrderDetail order) {
    return _card(
      label: 'Суммы',
      child: Column(
        children: [
          _sumRow('Товары', formatSomoni(order.subtotal)),
          _sumRow('Доставка', formatSomoni(order.deliveryFee)),
          if (order.discount > 0)
            _sumRow('Скидка', '−${formatSomoni(order.discount)}'),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Итого',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                formatSomoni(order.total),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 13.5)),
        ],
      ),
    );
  }
}

/// Пульсирующая точка LIVE-бейджа (макет 06-tracking).
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.secondary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
