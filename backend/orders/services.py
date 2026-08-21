"""Доменные сервисы заказов: переходы статусов, создание, отмена (api.md §3, §9)."""
import secrets
from decimal import Decimal, ROUND_HALF_UP

from django.contrib.gis.db.models.functions import Distance
from django.contrib.gis.geos import Point
from django.db import transaction

from catalog.models import Product, Shop
from catalog.services import is_open_at_moment, is_shop_open
from core.models import AuditLog
from delivery.models import Delivery
from marketing.models import PromoCode, PromoCodeUse

from .models import Order, OrderItem, OrderStatusHistory
from .state_machine import OrderStatus, validate_transition

TWO_PLACES = Decimal("0.01")


class OrderError(Exception):
    """Ошибка доменной логики заказа → {error:{code,message,details}}."""

    def __init__(self, code: str, message: str, http_status: int = 400, details=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status
        self.details = details or {}


def money(value) -> Decimal:
    return Decimal(value).quantize(TWO_PLACES, rounding=ROUND_HALF_UP)


def transition_order(order: Order, to_status: str, actor=None, comment: str = "") -> None:
    """Переход статуса строго по машине статусов + история + аудит (инвариант §5)."""
    validate_transition(order.status, to_status)
    before = order.status
    order.status = to_status
    order.save(update_fields=["status", "updated_at"])
    OrderStatusHistory.objects.create(
        order=order, status=to_status, changed_by=actor, comment=comment
    )
    AuditLog.objects.create(
        actor=actor,
        action="order.status_changed",
        entity_type="order",
        entity_id=order.id,
        before={"status": before},
        after={"status": to_status, "comment": comment},
    )


def _generate_number() -> str:
    for _ in range(20):
        number = f"F-{secrets.randbelow(1_000_000):06d}"
        if not Order.objects.filter(number=number).exists():
            return number
    raise OrderError("number_generation_failed", "Не удалось сгенерировать номер заказа", 500)


def _validate_promo(promo: PromoCode, user, subtotal: Decimal) -> None:
    from django.utils import timezone

    now = timezone.now()
    if not promo.is_active or not (promo.valid_from <= now <= promo.valid_to):
        raise OrderError("promo_invalid", "Промокод недействителен или истёк")
    if promo.max_uses is not None and promo.uses_count >= promo.max_uses:
        raise OrderError("promo_invalid", "Лимит использований промокода исчерпан")
    user_uses = PromoCodeUse.objects.filter(promo_code=promo, user=user).count()
    if user_uses >= promo.per_user_limit:
        raise OrderError(
            "promo_invalid", "Вы уже использовали этот промокод максимальное число раз"
        )
    if subtotal < promo.min_order_amount:
        raise OrderError(
            "promo_invalid",
            f"Минимальная сумма заказа для промокода — {promo.min_order_amount}",
            details={"min_order_amount": str(promo.min_order_amount)},
        )


def _promo_discount(promo: PromoCode, subtotal: Decimal, delivery_fee: Decimal) -> Decimal:
    if promo.type == PromoCode.Type.PERCENT:
        discount = money(subtotal * promo.value / Decimal("100"))
        return min(discount, subtotal)
    if promo.type == PromoCode.Type.FIXED:
        return min(money(promo.value), subtotal)
    return delivery_fee  # free_delivery


@transaction.atomic
def create_order(user, data: dict, idempotency_key=None) -> tuple[Order, bool]:
    """Создание заказа со всеми серверными проверками (api.md §3). Возвращает (order, created)."""
    if idempotency_key is not None:
        existing = Order.objects.filter(idempotency_key=idempotency_key).first()
        if existing is not None:
            if existing.client_id != user.id:
                raise OrderError(
                    "idempotency_conflict",
                    "Ключ идемпотентности уже использован другим заказом",
                    409,
                )
            return existing, False

    shop = Shop.objects.filter(pk=data["shop_id"]).prefetch_related("working_hours").first()
    if shop is None:
        raise OrderError("shop_not_found", "Магазин не найден", 404)
    if shop.status != Shop.Status.APPROVED:
        raise OrderError("shop_unavailable", "Магазин недоступен для заказов")

    # --- позиции: один магазин, в наличии ---
    items = data["items"]
    product_ids = [item["product_id"] for item in items]
    products = {p.id: p for p in Product.objects.filter(id__in=product_ids)}
    order_items = []
    for item in items:
        product = products.get(item["product_id"])
        if product is None or not product.is_active:
            raise OrderError(
                "product_unavailable",
                "Товар не найден",
                details={"product_id": item["product_id"]},
            )
        if product.shop_id != shop.id:
            raise OrderError(
                "different_shops",
                "Все товары заказа должны быть из одного магазина",
                details={"product_id": product.id},
            )
        if not product.is_available:
            raise OrderError(
                "product_unavailable",
                f"Товар «{product.name}» сейчас недоступен",
                details={"product_id": product.id},
            )
        order_items.append((product, item["qty"]))

    # --- слот: asap → магазин открыт; scheduled → в рабочие часы ---
    slot_type = data["slot_type"]
    scheduled_at = data.get("scheduled_at")
    if slot_type == Order.SlotType.ASAP:
        if not is_shop_open(shop):
            raise OrderError("shop_closed", "Магазин сейчас закрыт")
    else:
        from django.utils import timezone

        if scheduled_at is None:
            raise OrderError(
                "invalid_slot", "Для слота scheduled нужно указать scheduled_at"
            )
        if scheduled_at <= timezone.now():
            raise OrderError("invalid_slot", "scheduled_at должен быть в будущем")
        if not is_open_at_moment(shop, scheduled_at):
            raise OrderError(
                "shop_closed",
                "Выбранное время вне рабочих часов магазина",
                details={"scheduled_at": scheduled_at.isoformat()},
            )

    # --- точка доставки ∈ зоне магазина (PostGIS) ---
    address = data["address"]
    point = Point(float(address["lng"]), float(address["lat"]), srid=4326)
    zone = shop.zones.filter(is_active=True, polygon__contains=point).first()
    if zone is None:
        raise OrderError("out_of_zone", "Адрес вне зоны доставки магазина")

    # --- серверный расчёт сумм ---
    subtotal = money(sum(p.price * qty for p, qty in order_items))
    card_text = data.get("card_text", "")
    card_price = money(shop.card_price) if card_text else Decimal("0.00")
    subtotal += card_price

    min_order = max(shop.min_order_amount, zone.min_order_amount)
    if subtotal < min_order:
        raise OrderError(
            "min_order",
            f"Минимальная сумма заказа — {min_order}",
            details={"min_order": str(min_order), "subtotal": str(subtotal)},
        )

    distance_m = (
        Shop.objects.filter(pk=shop.pk).annotate(d=Distance("point", point)).first().d.m
    )
    delivery_fee = money(
        zone.base_price + zone.price_per_km * Decimal(distance_m) / Decimal("1000")
    )

    promo = None
    discount = Decimal("0.00")
    promo_code_str = (data.get("promo_code") or "").strip()
    if promo_code_str:
        promo = PromoCode.objects.filter(code__iexact=promo_code_str).first()
        if promo is None:
            raise OrderError("promo_invalid", "Промокод не найден")
        _validate_promo(promo, user, subtotal)
        discount = _promo_discount(promo, subtotal, delivery_fee)

    total = money(subtotal + delivery_fee - discount)

    order = Order.objects.create(
        number=_generate_number(),
        client=user,
        shop=shop,
        card_text=card_text,
        card_price=card_price,
        is_anonymous=data.get("is_anonymous", False),
        recipient_name=data["recipient_name"],
        recipient_phone=data["recipient_phone"],
        delivery_point=point,
        delivery_address_text=address["address_text"],
        delivery_details=address.get("details", ""),
        slot_type=slot_type,
        scheduled_at=scheduled_at if slot_type == Order.SlotType.SCHEDULED else None,
        subtotal=subtotal,
        delivery_fee=delivery_fee,
        discount=discount,
        total=total,
        commission_rate=shop.commission_rate,
        promo_code=promo,
        comment=data.get("comment", ""),
        idempotency_key=idempotency_key,
    )
    OrderItem.objects.bulk_create(
        [
            OrderItem(
                order=order,
                product=product,
                product_name=product.name,
                price=money(product.price),
                qty=qty,
                photo_url=(product.photos.first().image.url if product.photos.exists() else ""),
            )
            for product, qty in order_items
        ]
    )
    # PIN доставки генерируется при создании заказа (инвариант §8), курьер — позже
    Delivery.objects.create(order=order, pin_code=f"{secrets.randbelow(10_000):04d}")
    if promo is not None:
        PromoCodeUse.objects.create(promo_code=promo, user=user, order=order)
        promo.uses_count += 1
        promo.save(update_fields=["uses_count"])

    OrderStatusHistory.objects.create(order=order, status=OrderStatus.CREATED)

    from .tasks import ORDER_PAYMENT_TIMEOUT_SECONDS, expire_unpaid_order

    expire_unpaid_order.apply_async(
        (order.id,), countdown=ORDER_PAYMENT_TIMEOUT_SECONDS
    )
    return order, True


def release_promo(order: Order) -> None:
    """Освобождение промокода при отмене/истечении заказа."""
    if order.promo_code_id is None:
        return
    deleted, _ = PromoCodeUse.objects.filter(order=order).delete()
    if deleted:
        promo = order.promo_code
        promo.uses_count = max(0, promo.uses_count - 1)
        promo.save(update_fields=["uses_count"])


@transaction.atomic
def cancel_order_by_client(order: Order, user, reason: str = "") -> Decimal | None:
    """Отмена клиентом (api.md §3, business-logic.md §7). Возвращает сумму возврата."""
    from payments.services import create_auto_refund

    status = order.status
    full_refund_statuses = (
        OrderStatus.CREATED, OrderStatus.PAID, OrderStatus.SHOP_PENDING,
    )
    # Магазин принял/собирает — удержание 10% (компенсация начатой сборки).
    preparing_statuses = (OrderStatus.ACCEPTED, OrderStatus.PREPARING)
    # Букет собран/курьер назначен — удержание 20%.
    ready_statuses = (OrderStatus.READY, OrderStatus.COURIER_ASSIGNED)
    if status in full_refund_statuses:
        retention = Decimal("0.00")
    elif status in preparing_statuses + ready_statuses:
        from django.conf import settings

        percent = (
            settings.CANCEL_RETENTION_PREPARING_PERCENT
            if status in preparing_statuses
            else settings.CANCEL_RETENTION_READY_PERCENT
        )
        retention = money(order.total * Decimal(str(percent)) / 100)
    else:
        raise OrderError(
            "cannot_cancel",
            "Заказ уже у курьера — отмена только через поддержку",
            409,
        )

    refund_amount = None
    payment = order.payments.filter(status="success").first()
    if payment is not None:
        refund_amount = money(payment.amount - retention)
        if refund_amount > 0:
            create_auto_refund(payment, refund_amount, reason or "Отмена заказа клиентом")

    order.cancel_reason = reason
    order.save(update_fields=["cancel_reason", "updated_at"])
    transition_order(order, OrderStatus.CANCELLED_CLIENT, actor=user, comment=reason)
    release_promo(order)

    # WS + push: клиенту — статус, панели магазина — заказ отменён (api.md §7)
    from core import ws_events
    from core.push import send_push, send_push_many

    ws_events.notify_order_status(order)
    ws_events.notify_shop_order_cancelled(order)
    send_push(
        order.client, "order_status",
        {"order_id": order.id, "status": order.status},
    )
    send_push_many(
        [m.user for m in order.shop.staff.select_related("user")],
        "order_cancelled",
        {"order_id": order.id, "number": order.number},
    )
    return refund_amount
