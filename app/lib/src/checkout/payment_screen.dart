import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../api/models/order.dart';
import '../orders/order_detail_screen.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';

/// Оплата заказа (макет 05-payment): сумма из ответа сервера,
/// таймер резерва 15:00, способы оплаты (пока stub — тестовый режим).
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    required this.order,
    required this.idempotencyKey,
    required this.shopName,
    super.key,
  });

  final CreatedOrder order;

  /// Тот же ключ, что при создании заказа — повторный тап «Оплатить»
  /// не создаст второй платёж (api.md §4).
  final String idempotencyKey;
  final String shopName;

  /// Резерв неоплаченного заказа (api.md §3: TTL 15 минут).
  static const reserveDuration = Duration(minutes: 15);

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Duration _remaining = PaymentScreen.reserveDuration;
  Timer? _timer;
  String _method = 'alif'; // alif | dc — оба идут на stub-провайдер
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = _remaining > const Duration(seconds: 1)
            ? _remaining - const Duration(seconds: 1)
            : Duration.zero;
      });
      if (_remaining == Duration.zero) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _pay() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      // До договоров с банками оба кошелька ведут на provider "stub"
      // (api.md §4: фиктивный успешный платёж, только DEBUG/staging).
      final result = await context.read<ApiClient>().payOrder(
            orderId: widget.order.id,
            idempotencyKey: widget.idempotencyKey,
          );
      if (!mounted) return;
      if (result.isSuccess) {
        _timer?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => OrderSuccessScreen(orderId: widget.order.id),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Платёж не подтверждён, попробуйте ещё раз')),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining == Duration.zero;
    return Scaffold(
      appBar: AppBar(title: const Text('Оплата заказа')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          _buildSumCard(expired),
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 4, 2, 10),
            child: Text(
              'Способ оплаты',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          _methodTile(
            id: 'alif',
            name: 'Кошелёк Алиф',
            subtitle: 'Тестовый режим · спишется мгновенно',
            logoText: 'alif',
            logoColors: const [Color(0xFFE03131), Color(0xFFFF6B6B)],
          ),
          _methodTile(
            id: 'dc',
            name: 'Душанбе Сити',
            subtitle: 'Тестовый режим · кошелёк DC Next',
            logoText: 'DC',
            logoColors: const [Color(0xFF1971C2), Color(0xFF20C997)],
          ),
          _methodTile(
            id: 'card',
            name: 'Банковская карта',
            subtitle: 'Скоро · Visa / Mastercard / Корти Милли',
            logoText: '💳',
            logoColors: const [Color(0xFFADB5BD), Color(0xFFCED4DA)],
            enabled: false,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 14, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🔒', style: TextStyle(fontSize: 15)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Оплата проходит через защищённый шлюз банка. Деньги '
                    'резервируются на счёте платформы и переводятся магазину '
                    'только после доставки.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        child: ElevatedButton(
          onPressed: _paying || expired ? null : _pay,
          child: _paying
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  expired
                      ? 'Время резерва истекло'
                      : 'Оплатить ${formatSomoni(widget.order.total)}',
                ),
        ),
      ),
    );
  }

  Widget _buildSumCard(bool expired) {
    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 22),
      child: Column(
        children: [
          const Text(
            'К оплате',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            formatSomoni(widget.order.total),
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              color: expired ? AppColors.fill : AppColors.successSurface,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: expired
                      ? AppColors.textSecondary
                      : AppColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  expired
                      ? 'Резерв истёк — заказ будет отменён'
                      : 'Заказ зарезервирован на $minutes:$seconds',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: expired
                        ? AppColors.textSecondary
                        : AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'Заказ ${widget.order.number}'
            '${widget.shopName.isEmpty ? '' : ' · ${widget.shopName}'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _methodTile({
    required String id,
    required String name,
    required String subtitle,
    required String logoText,
    required List<Color> logoColors,
    bool enabled = true,
  }) {
    final selected = _method == id;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.border,
            width: 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => setState(() => _method = id) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: logoColors,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    logoText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.textPrimary : null,
                    border: Border.all(
                      color: selected
                          ? AppColors.textPrimary
                          : const Color(0xFFD6D6D6),
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Экран «Заказ оплачен»: номер, статус, переход к отслеживанию.
class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({required this.orderId, super.key});

  final int orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    color: AppColors.successSurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 44,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Заказ оплачен',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Магазин получил заказ и скоро подтвердит его. '
                  'Мы пришлём уведомление о смене статуса.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderDetailScreen(orderId: orderId),
                    ),
                  ),
                  child: const Text('Отслеживать'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .popUntil((route) => route.isFirst),
                  child: const Text('На главную'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
