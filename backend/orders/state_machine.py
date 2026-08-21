"""
Машина статусов заказа (business-logic.md §3, api.md §9).

Только каркас: константы, таблица допустимых переходов и валидация.
Побочные эффекты переходов (возвраты, push, начисления) — следующий этап.
"""
from django.core.exceptions import ValidationError


class OrderStatus:
    CREATED = "created"
    PAYMENT_FAILED = "payment_failed"
    EXPIRED = "expired"
    PAID = "paid"
    SHOP_PENDING = "shop_pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    TIMEOUT = "timeout"
    PREPARING = "preparing"
    READY = "ready"
    COURIER_ASSIGNED = "courier_assigned"
    PICKED_UP = "picked_up"
    ON_THE_WAY = "on_the_way"
    ARRIVED = "arrived"
    DELIVERED = "delivered"
    COMPLETED = "completed"
    CANCELLED_CLIENT = "cancelled_client"
    CANCELLED_SHOP = "cancelled_shop"
    CANCELLED_ADMIN = "cancelled_admin"
    DISPUTED = "disputed"

    CANCELLABLE = (
        # «любой до picked_up → cancelled_*»
        CREATED, PAID, SHOP_PENDING, ACCEPTED, PREPARING, READY, COURIER_ASSIGNED,
    )
    CANCELLATIONS = (CANCELLED_CLIENT, CANCELLED_SHOP, CANCELLED_ADMIN)
    TERMINAL = (
        PAYMENT_FAILED, EXPIRED, REJECTED, TIMEOUT, COMPLETED,
        CANCELLED_CLIENT, CANCELLED_SHOP, CANCELLED_ADMIN,
    )


# Таблица допустимых переходов (api.md §9)
ALLOWED_TRANSITIONS: dict[str, frozenset[str]] = {
    OrderStatus.CREATED: frozenset(
        {OrderStatus.PAYMENT_FAILED, OrderStatus.EXPIRED, OrderStatus.PAID}
    ),
    OrderStatus.PAID: frozenset({OrderStatus.SHOP_PENDING}),
    OrderStatus.SHOP_PENDING: frozenset(
        {OrderStatus.ACCEPTED, OrderStatus.REJECTED, OrderStatus.TIMEOUT}
    ),
    OrderStatus.ACCEPTED: frozenset({OrderStatus.PREPARING}),
    OrderStatus.PREPARING: frozenset({OrderStatus.READY}),
    OrderStatus.READY: frozenset({OrderStatus.COURIER_ASSIGNED}),
    OrderStatus.COURIER_ASSIGNED: frozenset({OrderStatus.PICKED_UP}),
    OrderStatus.PICKED_UP: frozenset({OrderStatus.ON_THE_WAY}),
    OrderStatus.ON_THE_WAY: frozenset({OrderStatus.ARRIVED}),
    OrderStatus.ARRIVED: frozenset({OrderStatus.DELIVERED}),
    OrderStatus.DELIVERED: frozenset({OrderStatus.COMPLETED, OrderStatus.DISPUTED}),
    OrderStatus.DISPUTED: frozenset(),  # TODO: решение спора → completed/возврат (этап платежей)
}
# Отмены из любого статуса до picked_up
for _status in OrderStatus.CANCELLABLE:
    ALLOWED_TRANSITIONS[_status] = ALLOWED_TRANSITIONS.get(_status, frozenset()) | frozenset(
        OrderStatus.CANCELLATIONS
    )
# Терминальные статусы — без исходящих переходов
for _status in OrderStatus.TERMINAL:
    ALLOWED_TRANSITIONS.setdefault(_status, frozenset())


def allowed_next(status: str) -> frozenset[str]:
    return ALLOWED_TRANSITIONS.get(status, frozenset())


def can_transition(from_status: str, to_status: str) -> bool:
    return to_status in allowed_next(from_status)


def validate_transition(from_status: str, to_status: str) -> None:
    """Бросает ValidationError, если переход недопустим."""
    if not can_transition(from_status, to_status):
        raise ValidationError(
            f"Недопустимый переход статуса заказа: {from_status} → {to_status}"
        )
