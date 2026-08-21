import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/order.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_screen.dart';
import '../common/widgets/app_network_image.dart';
import '../shell/main_shell.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';
import 'order_detail_screen.dart';

/// Раздел «Заказы» (макет v5 04-orders): заголовок + корзина, чипы
/// Все / Активные / Завершённые (GET /orders/?status=…), карточки заказов.
/// Stateful, чтобы MainShell мог дёрнуть reload() при выборе вкладки —
/// иначе свежий заказ после оплаты не виден до перезахода.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => OrdersScreenState();
}

class OrdersScreenState extends State<OrdersScreen> {
  static const _filters = <String?>[null, 'active', 'history'];

  int _chip = 0;
  final _tabKeys = List.generate(3, (_) => GlobalKey<_OrdersTabState>());

  void reload() {
    for (final key in _tabKeys) {
      key.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _OrdersHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  for (var i = 0; i < _filters.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _FilterChip(
                      label: const ['Все', 'Активные', 'Завершённые'][i],
                      selected: _chip == i,
                      onTap: () => setState(() => _chip = i),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _chip,
                children: [
                  for (var i = 0; i < _filters.length; i++)
                    _OrdersTab(key: _tabKeys[i], filter: _filters[i]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Заголовок «Мои заказы» + круглая кнопка корзины с бейджем (макет 04).
class _OrdersHeader extends StatelessWidget {
  const _OrdersHeader();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Мои заказы',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppColors.textPrimary,
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CartScreen()),
            ),
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: AppColors.fill,
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                  if (!cart.isEmpty)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 19),
                        height: 19,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          '${cart.totalCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.fill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({super.key, required this.filter});

  /// null — все заказы, иначе `active` / `history` (GET /orders/?status=…).
  final String? filter;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab>
    with AutomaticKeepAliveClientMixin {
  List<OrderSummary>? _orders;
  String? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  /// Публичная перезагрузка — вызывается OrdersScreenState.reload().
  void reload() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _orders == null;
      _error = null;
    });
    try {
      final page = await context
          .read<ApiClient>()
          .fetchOrders(filter: widget.filter);
      if (!mounted) return;
      setState(() {
        _orders = page.results;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _load,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null) {
      return _CenteredScrollable(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style:
                  ElevatedButton.styleFrom(minimumSize: const Size(160, 44)),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    final orders = _orders!;
    if (orders.isEmpty) {
      return _CenteredScrollable(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              switch (widget.filter) {
                'active' => 'Нет активных заказов',
                'history' => 'История заказов пуста',
                _ => 'Заказов пока нет',
              },
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, kFloatingTabBarClearance),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) =>
          _OrderCard(order: orders[index], onReturn: _load),
    );
  }
}

/// Обертка для состояний ошибки/пустоты, чтобы работал pull-to-refresh.
class _CenteredScrollable extends StatelessWidget {
  const _CenteredScrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Формат даты без локали: «07.08, 14:32».
String formatOrderDate(DateTime? dt) {
  if (dt == null) return '';
  final local = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}, ${two(local.hour)}:${two(local.minute)}';
}

/// Цвет пилюли статуса (v5): живые и успешные — зелёные, отмены — серые.
(Color, Color) orderStatusColors(String status) {
  final failed = orderStatusIsFinal(status) &&
      status != 'delivered' &&
      status != 'completed';
  if (failed) {
    return (AppColors.textSecondary, AppColors.fill);
  }
  return (AppColors.accent, AppColors.successSurface);
}

/// Карточка заказа (макет 04-orders): лого магазина слева, номер + сумма,
/// магазин/дата серым, пилюля статуса + кнопка «Детали».
class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.onReturn});

  final OrderSummary order;

  /// Обновить список при возврате с экрана деталей
  /// (статус мог измениться за время просмотра).
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = orderStatusColors(order.status);
    final isFinal = orderStatusIsFinal(order.status);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context)
            .push(
              MaterialPageRoute<void>(
                builder: (_) => OrderDetailScreen(orderId: order.id),
              ),
            )
            .then((_) => onReturn?.call()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: AppNetworkImage(
                    url: order.shopLogo,
                    height: 56,
                    placeholderSeed: order.shopId,
                    placeholderIcon: Icons.storefront,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Заказ ${order.number}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        Text(
                          formatSomoni(order.total),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${order.shopName} · ${formatOrderDate(order.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(999),
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
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isFinal
                                ? AppColors.fill
                                : AppColors.textPrimary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Детали',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isFinal
                                  ? AppColors.textPrimary
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
