import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Экран «Правила возврата» — тот же текст, что в docs/refund-policy.md.
/// Стиль v5: белый фон, чёрные заголовки, воздух между секциями.
class RefundPolicyScreen extends StatelessWidget {
  const RefundPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Правила возврата')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [
          _Lead(
            'Мы хотим, чтобы вы заказывали цветы спокойно. Вот честно и без '
            'мелкого шрифта, сколько денег вернётся в каждой ситуации.',
          ),
          _Section(
            title: 'Если отменяете вы',
            paragraphs: [
              'Возврат зависит от этапа заказа. Чем дальше продвинулся заказ, '
                  'тем больше труда магазин уже вложил — поэтому часть суммы '
                  'удерживается как компенсация.',
            ],
            bullets: [
              ('Заказ ещё не оплачен',
                  'отменяется свободно, платить не нужно.'),
              ('Оплачен, магазин ещё не принял заказ',
                  'возврат 100% — вся сумма.'),
              ('Магазин принял заказ и собирает букет',
                  'возврат 90% — удерживаем 10% за начатую сборку.'),
              ('Букет собран или курьер уже назначен',
                  'возврат 80% — удерживаем 20%: работа магазина почти закончена.'),
              ('Курьер забрал букет у магазина',
                  'отменить в приложении уже нельзя — напишите в поддержку, разберёмся вместе.'),
            ],
            footer: 'Деньги возвращаются на тот же кошелёк, с которого вы '
                'платили (Алиф или Душанбе Сити), — обычно в течение '
                'нескольких минут.',
          ),
          _Section(
            title: 'Если заказ не состоялся по нашей вине',
            bullets: [
              ('Магазин отклонил заказ',
                  'вернём 100% и предложим похожий букет в другом магазине.'),
              ('Магазин не ответил вовремя',
                  'заказ отменяется автоматически, вернём 100%.'),
            ],
          ),
          _Section(
            title: 'Если что-то пошло не так при доставке',
            bullets: [
              ('Получатель не отвечает и не встречает курьера',
                  'курьер подождёт и позвонит несколько раз, но если связаться '
                      'не удаётся, заказ считается доставленным и деньги, '
                      'к сожалению, не возвращаются — букет уже собран и привезён. '
                      'Проверяйте телефон получателя при оформлении.'),
              ('Привезли не то или цветы вялые',
                  'откройте спор в приложении в течение 24 часов после доставки '
                      'и приложите фото. Поддержка разберётся не дольше чем за '
                      '24 часа и вернёт деньги полностью или частично — по итогам проверки.'),
            ],
          ),
          _Section(
            title: 'Остались вопросы',
            paragraphs: [
              'Напишите в поддержку из раздела «Помощь» — отвечаем быстро '
                  'и всегда на стороне справедливости.',
            ],
          ),
        ],
      ),
    );
  }
}

/// Открыть экран правил возврата (из профиля и с экрана оформления).
void openRefundPolicy(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const RefundPolicyScreen()),
  );
}

class _Lead extends StatelessWidget {
  const _Lead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 22),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    this.paragraphs = const [],
    this.bullets = const [],
    this.footer,
  });

  final String title;
  final List<String> paragraphs;

  /// (жирное начало, продолжение обычным).
  final List<(String, String)> bullets;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: AppColors.textPrimary,
            ),
          ),
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                p,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          for (final (bold, rest) in bullets)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle,
                        size: 5, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$bold — ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: rest),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                footer!,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
