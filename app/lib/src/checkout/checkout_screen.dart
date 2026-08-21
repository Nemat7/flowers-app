import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import '../cart/cart_controller.dart';
import '../profile/refund_policy_screen.dart';
import '../theme/colors.dart';
import '../theme/formatters.dart';
import 'checkout_controller.dart';
import 'payment_screen.dart';

/// Оформление заказа (макет 04-checkout): адрес, слот, получатель,
/// открытка, комментарий, промокод, итоги, «Перейти к оплате».
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late final CheckoutController _controller;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cardTextController = TextEditingController();
  final _commentController = TextEditingController();
  final _promoController = TextEditingController();

  String _slotType = 'asap';
  DateTime? _scheduledAt;
  bool _isAnonymous = false;
  bool _promoApplied = false;

  static const int _cardTextLimit = 300;

  @override
  void initState() {
    super.initState();
    // Контроллер живёт, пока открыт экран: ключ идемпотентности один
    // на попытку оформления, повторные тапы не плодят заказы.
    _controller = CheckoutController(apiClient: context.read<ApiClient>());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cardTextController.dispose();
    _commentController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_nameController.text.trim().isEmpty) {
      return 'Укажите имя получателя';
    }
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 9) {
      return 'Введите телефон получателя: 9 цифр после +992';
    }
    if (_slotType == 'scheduled') {
      if (_scheduledAt == null) return 'Выберите дату и время доставки';
      if (_scheduledAt!.isBefore(DateTime.now())) {
        return 'Время доставки уже прошло';
      }
    }
    return null;
  }

  Future<void> _pickScheduled() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 2))),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final cart = context.read<CartController>();
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    try {
      final order = await _controller.submit(
        cart: cart,
        recipientName: _nameController.text,
        recipientPhone: '+992$digits',
        isAnonymous: _isAnonymous,
        slotType: _slotType,
        scheduledAt: _scheduledAt,
        cardText: _cardTextController.text,
        comment: _commentController.text,
        promoCode: _promoApplied ? _promoController.text : '',
      );
      if (!mounted) return;
      final shopName = cart.shopName;
      cart.clear(); // заказ создан — корзина больше не нужна
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PaymentScreen(
            order: order,
            idempotencyKey: _controller.idempotencyKey,
            shopName: shopName ?? '',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Оформление заказа')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        children: [
          _buildAddressCard(),
          _buildSlotCard(),
          _buildRecipientCard(),
          _buildCardTextCard(),
          _buildPromoCard(),
          _buildTotalsCard(cart),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => ElevatedButton(
                onPressed: _controller.submitting ? null : _submit,
                child: _controller.submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Перейти к оплате'),
              ),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Оформляя заказ, вы принимаете '),
                  TextSpan(
                    text: 'правила возврата',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => openRefundPolicy(context),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String label, required Widget child}) {
    // v5: секции без карточек — заголовок капсом + контент на белом.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.7,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return _sectionCard(
      label: 'Адрес доставки',
      child: const Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.fill,
            child: Icon(Icons.location_on_outlined,
                color: AppColors.textPrimary, size: 20),
          ),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ул. Рудаки 25',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  'TODO: выбор адреса по геолокации',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard() {
    return _sectionCard(
      label: 'Время доставки',
      child: Row(
        children: [
          Expanded(
            child: _slotTile(
              selected: _slotType == 'asap',
              title: 'Как можно скорее',
              subtitle: 'Сегодня, 35–45 минут',
              onTap: () => setState(() => _slotType = 'asap'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _slotTile(
              selected: _slotType == 'scheduled',
              title: 'Ко времени',
              subtitle: _scheduledAt == null
                  ? 'Выбрать дату и слот'
                  : _formatScheduled(_scheduledAt!),
              onTap: () async {
                setState(() => _slotType = 'scheduled');
                await _pickScheduled();
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatScheduled(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _slotTile({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    // v5: пилюли — выбранная чёрная, остальные серые.
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary : AppColors.fill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Column(
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientCard() {
    return _sectionCard(
      label: 'Получатель',
      child: Column(
        children: [
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Имя получателя'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: const InputDecoration(
              hintText: '90 123 45 67',
              prefixText: '+992 ',
            ),
          ),
          const SizedBox(height: 4),
          // Зелёный свитч вместо чекбокса (макет 07-checkout).
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Анонимная доставка',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Курьер не назовёт имя отправителя, открытка — без подписи',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isAnonymous,
                onChanged: (value) => setState(() => _isAnonymous = value),
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardTextCard() {
    return _sectionCard(
      label: 'Текст открытки · бесплатно',
      child: Column(
        children: [
          TextField(
            controller: _cardTextController,
            maxLength: _cardTextLimit,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: 'С днём рождения, родная! …',
              counterStyle:
                  TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
          ),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              hintText: 'Комментарий для магазина или курьера…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard() {
    return _sectionCard(
      label: 'Промокод',
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promoController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'SPRING10',
                helperText: _promoApplied
                    ? 'Промокод будет проверен при создании заказа'
                    : null,
                helperStyle: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              onChanged: (_) {
                if (_promoApplied) setState(() => _promoApplied = false);
              },
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              if (_promoController.text.trim().isEmpty) return;
              setState(() => _promoApplied = true);
              FocusScope.of(context).unfocus();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              backgroundColor: AppColors.successSurface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(_promoApplied ? 'Применён ✓' : 'Применить'),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsCard(CartController cart) {
    return _sectionCard(
      label: 'Итоги',
      child: Column(
        children: [
          for (final item in cart.items)
            _totalRow(
              '${item.product.name} × ${item.qty}',
              formatSomoni(item.lineTotal),
            ),
          const _TotalRow(
            'Доставка',
            'рассчитается при создании заказа',
          ),
          if (_promoApplied)
            const _TotalRow('Промокод', 'проверяется на сервере'),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Товары',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              Text(
                formatSomoni(cart.subtotal),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'итоговая сумма — на экране оплаты',
              style: TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) => _TotalRow(label, value);
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
