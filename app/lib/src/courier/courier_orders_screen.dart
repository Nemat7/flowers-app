import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/models/courier.dart';
import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';
import '../theme/theme.dart';
import 'courier_controller.dart';
import 'courier_ws.dart';
import 'location_tracker.dart';

/// Главный экран курьера: переключатель «На линии», доступные заказы
/// и активный заказ-шагер. Минимум тапов — курьер за рулём.
class CourierOrdersScreen extends StatefulWidget {
  const CourierOrdersScreen({super.key});

  @override
  State<CourierOrdersScreen> createState() => _CourierOrdersScreenState();
}

class _CourierOrdersScreenState extends State<CourierOrdersScreen> {
  late final CourierWsService _ws;
  late final CourierController _controller;

  @override
  void initState() {
    super.initState();
    _ws = CourierWsService(
      tokenStorage: context.read<TokenStorage>(),
      authRepository: context.read<AuthRepository>(),
    );
    _controller = CourierController(
      apiClient: context.read<ApiClient>(),
      wsService: _ws,
      positionStream: geolocatorPositionStream,
    );
    _controller.addListener(_onControllerChanged);
    _controller.init();
  }

  void _onControllerChanged() {
    final notice = _controller.notice;
    if (notice != null && mounted) {
      _controller.clearNotice();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Заказы')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final controller = _controller;
          return Column(
            children: [
              _LineToggle(
                lineStatus: controller.lineStatus,
                onChanged: controller.actionInProgress
                    ? null
                    : controller.setOnLine,
              ),
              Expanded(child: _buildBody(controller)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(CourierController controller) {
    if (controller.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (controller.loadError != null && !controller.isOnLine) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(controller.loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: controller.init,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(160, 44),
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (!controller.isOnLine) {
      return const _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.power_settings_new, size: 48, color: AppColors.textHint),
            SizedBox(height: 12),
            Text(
              'Вы не на линии',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Включите переключатель сверху,\nчтобы получать заказы',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }
    final current = controller.current;
    if (current != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: _ActiveOrderCard(order: current, controller: controller),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: controller.refreshAvailable,
      child: controller.available.isEmpty
          ? const _Centered(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 48, color: AppColors.textHint),
                  SizedBox(height: 12),
                  Text(
                    'Пока нет доступных заказов',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Новые заказы появятся автоматически',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: controller.available.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) => _AvailableOrderCard(
                order: controller.available[index],
                busy: controller.actionInProgress,
                onAccept: () =>
                    controller.acceptOrder(controller.available[index].id),
              ),
            ),
    );
  }
}

/// Обертка для состояний-заглушек, чтобы работал pull-to-refresh.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    );
  }
}

/// Большой переключатель «На линии» — статус виден всегда.
class _LineToggle extends StatelessWidget {
  const _LineToggle({required this.lineStatus, required this.onChanged});

  final String lineStatus;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final onLine = lineStatus != 'offline';
    final busy = lineStatus == 'busy';
    final color = onLine ? AppColors.secondary : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: onLine ? AppColors.successSurface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: kCardShadow,
      ),
      child: Row(
        children: [
          Icon(
            onLine ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  busy
                      ? 'Заказ в работе'
                      : onLine
                          ? 'Вы на линии'
                          : 'Вы не на линии',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  busy
                      ? 'Завершите доставку, чтобы уйти offline'
                      : onLine
                          ? 'Вам доступны новые заказы'
                          : 'Заказы не приходят',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 1.2,
            child: Switch(
              value: onLine,
              onChanged: onChanged,
              activeTrackColor: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка доступного заказа: магазин → адрес, заработок, «Принять».
class _AvailableOrderCard extends StatelessWidget {
  const _AvailableOrderCard({
    required this.order,
    required this.busy,
    required this.onAccept,
  });

  final CourierOrder order;
  final bool busy;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: kCardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.number,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '+${formatSomoni(order.deliveryFee)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AddressRow(
            icon: Icons.storefront,
            title: order.shop.name,
            subtitle: order.shop.addressText,
          ),
          const SizedBox(height: 6),
          _AddressRow(
            icon: Icons.location_on_outlined,
            title: order.address.addressText,
            subtitle: [
              if (order.distance != null) formatDistance(order.distance),
              if ((order.address.details ?? '').isNotEmpty)
                order.address.details!,
            ].join(' · '),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: busy ? null : onAccept,
              child: const Text('Принять', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textHint),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Активный заказ — карточка-шагер: магазин → получатель → PIN.
class _ActiveOrderCard extends StatefulWidget {
  const _ActiveOrderCard({required this.order, required this.controller});

  final CourierOrder order;
  final CourierController controller;

  @override
  State<_ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<_ActiveOrderCard> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) return;
    final success = await widget.controller.completeOrder(pin);
    if (success) _pinController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final controller = widget.controller;
    final step = controller.step ?? CourierStep.toShop;
    final (actionLabel, action) = switch (step) {
      CourierStep.toShop => ('Забрал заказ', controller.pickupOrder),
      CourierStep.toRecipient => ('Я на месте', controller.arriveOrder),
      CourierStep.confirmPin => ('Завершить', _complete),
    };
    final destination = step == CourierStep.toShop
        ? (lat: order.shop.lat, lng: order.shop.lng)
        : (lat: order.address.lat, lng: order.address.lng);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: kCardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.number,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '+${formatSomoni(order.fee ?? order.deliveryFee)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AddressRow(
            icon: Icons.storefront,
            title: order.shop.name,
            subtitle: order.shop.addressText,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.arrow_downward,
                size: 16, color: AppColors.textHint),
          ),
          _AddressRow(
            icon: Icons.location_on_outlined,
            title: order.address.addressText,
            subtitle: order.address.details ?? '',
          ),
          if (step != CourierStep.toShop) ...[
            const SizedBox(height: 10),
            _RecipientRow(order: order),
          ],
          if (controller.locationWarning) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.location_off, size: 18, color: AppColors.star),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Нет доступа к геолокации — клиент не видит вас на карте',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (destination.lat != null && destination.lng != null)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _openRoute(
                  destination.lat!,
                  destination.lng!,
                ),
                icon: const Icon(Icons.route, color: AppColors.accent),
                label: const Text(
                  'Маршрут',
                  style: TextStyle(color: AppColors.accent, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          if (step == CourierStep.confirmPin) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _complete(),
              decoration: InputDecoration(
                labelText: 'PIN-код получателя',
                hintText: '4 цифры из приложения клиента',
                errorText: controller.pinError,
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: controller.actionInProgress ||
                      (step == CourierStep.confirmPin &&
                          _pinController.text.trim().length < 4)
                  ? null
                  : action,
              child: controller.actionInProgress
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(actionLabel, style: const TextStyle(fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRoute(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Получатель: имя + телефон с кнопкой звонка.
class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.order});

  final CourierOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline,
              size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.recipientName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  order.recipientPhone,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => launchUrl(
              Uri(scheme: 'tel', path: order.recipientPhone),
            ),
            icon: const Icon(Icons.call, color: AppColors.secondary),
            tooltip: 'Позвонить получателю',
          ),
        ],
      ),
    );
  }
}
