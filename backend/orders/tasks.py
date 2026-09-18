"""Фоновые задачи заказов (таймауты, авто-завершение).

Запуск по мере событий (не beat-расписание): при создании заказа ставится
`expire_unpaid_order.apply_async((order_id,), countdown=ORDER_PAYMENT_TIMEOUT_SECONDS)`,
при переводе в shop_pending — `shop_response_timeout(...)`, при delivered —
`complete_delivered_order(...)`.

Все задачи идемпотентны: перед изменением проверяют актуальный статус заказа
(гонка с ручными действиями — no-op).
"""
from decimal import Decimal

from celery import shared_task
from django.db import transaction

from .models import Order
from .services import release_promo, transition_order
from .state_machine import OrderStatus

ORDER_PAYMENT_TIMEOUT_SECONDS = 15 * 60  # created → expired
SHOP_ACCEPT_TIMEOUT_SECONDS = 5 * 60  # shop_pending → timeout (5–7 мин, настраивается)
DELIVERED_COMPLETE_TIMEOUT_SECONDS = 2 * 3600  # delivered → completed (2 ч без спора)

SHOP_HIDE_TIMEOUT_STREAK = 3  # 3 таймаута подряд → авто-скрытие из выдачи (api.md §5)


@shared_task
def expire_unpaid_order(order_id: int) -> None:
    """created → expired через 15 мин без оплаты; слот и промокод освобождаются."""
    try:
        order = Order.objects.get(pk=order_id)
    except Order.DoesNotExist:
        return
    if order.status != OrderStatus.CREATED:
        return  # гонка: заказ уже оплачен/отменён — no-op
    with transaction.atomic():
        transition_order(order, OrderStatus.EXPIRED, comment="Не оплачен за 15 минут")
        release_promo(order)
    from core import ws_events
    from core.push import send_push

    ws_events.notify_order_status(order)
    send_push(order.client, "order_expired", {"order_id": order.id})


@shared_task
def shop_response_timeout(order_id: int) -> None:
    """shop_pending → timeout, авто-возврат, штрафной счётчик магазину (api.md §5)."""
    from payments.services import create_auto_refund

    try:
        order = Order.objects.select_related("shop").get(pk=order_id)
    except Order.DoesNotExist:
        return
    if order.status != OrderStatus.SHOP_PENDING:
        return  # гонка: магазин уже ответил — no-op
    with transaction.atomic():
        payment = order.payments.filter(status="success").first()
        if payment is not None:
            create_auto_refund(payment, payment.amount, "Магазин не ответил вовремя")
        order.cancel_reason = "Магазин не ответил вовремя"
        order.save(update_fields=["cancel_reason", "updated_at"])
        transition_order(order, OrderStatus.TIMEOUT)
        release_promo(order)

        shop = order.shop
        shop.consecutive_timeouts += 1
        update_fields = ["consecutive_timeouts", "updated_at"]
        if shop.consecutive_timeouts >= SHOP_HIDE_TIMEOUT_STREAK:
            # 3 подряд → авто-скрытие из выдачи (статус остаётся approved)
            shop.is_hidden = True
            update_fields.append("is_hidden")
        shop.save(update_fields=update_fields)
    from core import ws_events
    from core.push import send_push, send_push_many

    ws_events.notify_order_status(order)
    ws_events.notify_shop_order_cancelled(order)
    send_push(order.client, "order_timeout", {"order_id": order.id})
    send_push_many(
        [m.user for m in order.shop.staff.select_related("user")],
        "order_cancelled",
        {"order_id": order.id, "number": order.number},
    )


@shared_task
def complete_delivered_order(order_id: int) -> None:
    """delivered → completed через 2 ч без спора + начисление в ledger магазина."""
    from payments.models import ShopBalanceTransaction

    try:
        order = Order.objects.select_related("shop").get(pk=order_id)
    except Order.DoesNotExist:
        return
    if order.status != OrderStatus.DELIVERED:
        return  # гонка: заказ ушёл в спор/завершён — no-op

    with transaction.atomic():
        shop = order.shop
        commission = (order.subtotal * order.commission_rate / Decimal("100")).quantize(
            Decimal("0.01")
        )
        order.commission_amount = commission
        order.save(update_fields=["commission_amount", "updated_at"])
        transition_order(order, OrderStatus.COMPLETED)

        balance = (
            ShopBalanceTransaction.objects.filter(shop=shop)
            .order_by("-id")
            .values_list("balance_after", flat=True)
            .first()
            or Decimal("0")
        )
        accrual_balance = balance + order.subtotal
        ShopBalanceTransaction.objects.create(
            shop=shop,
            order=order,
            type=ShopBalanceTransaction.Type.ACCRUAL,
            amount=order.subtotal,
            balance_after=accrual_balance,
            comment=f"Начисление по заказу {order.number}",
        )
        ShopBalanceTransaction.objects.create(
            shop=shop,
            order=order,
            type=ShopBalanceTransaction.Type.COMMISSION,
            amount=-commission,
            balance_after=accrual_balance - commission,
            comment=f"Комиссия платформы {order.commission_rate}% по заказу {order.number}",
        )
    from core import ws_events
    from core.push import send_push

    ws_events.notify_order_status(order)
    send_push(order.client, "order_status", {"order_id": order.id, "status": order.status})


@shared_task
def notify_shop_new_order_sms(order_id: int) -> None:
    """SMS магазину о новом оплаченном заказе (на случай, если панель не открыта)."""
    from accounts.sms import send_sms

    try:
        order = Order.objects.select_related("shop").get(pk=order_id)
    except Order.DoesNotExist:
        return
    phone = order.shop.phone
    if not phone:
        return
    send_sms(
        phone,
        f"Flowers&Swts: новый заказ {order.number} на {order.total} c. "
        "Откройте панель магазина и примите заказ.",
    )
