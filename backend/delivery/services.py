"""Доменные сервисы курьера: линия, приём заказа, доставка, трекинг (api.md §6).

Все переходы статусов заказа — через orders.services.transition_order
(машина статусов + OrderStatusHistory + AuditLog), побочные эффекты —
WS-события (core/ws_events) и push-заглушка (core/push).
"""
from datetime import datetime, UTC

from django.contrib.gis.geos import Point
from django.core.cache import cache
from django.db import transaction
from django.utils import timezone

from core import ws_events
from core.push import send_push
from orders.models import Order
from orders.services import transition_order
from orders.state_machine import OrderStatus

from .models import CourierLocation, CourierProfile, Delivery

# Заказ «в работе» у курьера — один за раз (api.md §6)
ACTIVE_ORDER_STATUSES = (
    OrderStatus.COURIER_ASSIGNED,
    OrderStatus.PICKED_UP,
    OrderStatus.ON_THE_WAY,
    OrderStatus.ARRIVED,
)
# Статусы, при которых принимаются GPS-точки и идёт трекинг
TRACKING_STATUSES = (
    OrderStatus.PICKED_UP,
    OrderStatus.ON_THE_WAY,
    OrderStatus.ARRIVED,
)

COURIER_LOC_CACHE_TTL_SECONDS = 60  # живая позиция в Redis (courier:loc:{id})
TRACK_SAVE_INTERVAL_SECONDS = 20  # прореживание записи в CourierLocation


class DeliveryError(Exception):
    """Ошибка доменной логики доставки → {error:{code,message,details}}."""

    def __init__(self, code: str, message: str, http_status: int = 400, details=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status
        self.details = details or {}


def get_active_delivery(profile: CourierProfile) -> Delivery | None:
    """Активная доставка курьера (заказ courier_assigned..arrived)."""
    return (
        Delivery.objects.filter(courier=profile, order__status__in=ACTIVE_ORDER_STATUSES)
        .select_related("order", "order__shop")
        .first()
    )


def set_courier_status(profile: CourierProfile, target: str) -> CourierProfile:
    """Выход/уход с линии. Offline запрещён при активном заказе."""
    active = get_active_delivery(profile)
    if target == CourierProfile.Status.OFFLINE and active is not None:
        raise DeliveryError(
            "active_delivery",
            "Нельзя уйти offline с активным заказом — сначала завершите доставку",
            409,
        )
    # busy управляется системой (accept/complete), вручную не выставляется
    profile.status = CourierProfile.Status.BUSY if active is not None else target
    profile.save(update_fields=["status"])
    ws_events.set_courier_online(
        profile.user_id, online=profile.status != CourierProfile.Status.OFFLINE
    )
    return profile


def available_orders() -> list[Order]:
    """Заказы ready без курьера (назначение в MVP — кто первый принял)."""
    return list(
        Order.objects.filter(status=OrderStatus.READY, delivery__courier__isnull=True)
        .select_related("shop", "delivery")
        .order_by("created_at")
    )


def _get_order_for_courier(order_id: int) -> Order:
    order = Order.objects.filter(pk=order_id).first()
    if order is None:
        raise DeliveryError("not_found", "Заказ не найден", 404)
    return order


@transaction.atomic
def accept_order(profile: CourierProfile, order_id: int) -> Order:
    """Взять заказ: только из ready, курьер online и без активного заказа.

    Гонка двух курьеров: строка заказа и доставки блокируется
    (select_for_update), второй получает 409 order_taken.
    """
    if get_active_delivery(profile) is not None:
        raise DeliveryError(
            "active_delivery", "У вас уже есть активный заказ — один за раз", 409
        )
    if profile.status != CourierProfile.Status.ONLINE:
        raise DeliveryError(
            "courier_offline", "Чтобы взять заказ, выйдите на линию (online)", 400
        )

    order = _get_order_for_courier(order_id)
    locked = Order.objects.select_for_update().get(pk=order.pk)
    delivery = Delivery.objects.select_for_update().get(order=locked)
    if delivery.courier_id is not None:
        raise DeliveryError("order_taken", "Заказ уже забрал другой курьер", 409)
    if locked.status != OrderStatus.READY:
        raise DeliveryError(
            "invalid_state", f"Заказ в статусе «{locked.status}», взять нельзя", 409
        )

    now = timezone.now()
    delivery.courier = profile
    delivery.fee = locked.delivery_fee  # заработок курьера = стоимость доставки
    delivery.assigned_at = now
    delivery.save(update_fields=["courier", "fee", "assigned_at"])
    transition_order(locked, OrderStatus.COURIER_ASSIGNED, actor=profile.user)
    profile.status = CourierProfile.Status.BUSY
    profile.save(update_fields=["status"])

    ws_events.notify_order_status(locked)
    ws_events.notify_couriers_order_taken(locked)
    send_push(locked.client, "order_status", {"order_id": locked.id, "status": locked.status})
    return locked


def _courier_order(profile: CourierProfile, order_id: int) -> Order:
    """Заказ, назначенный этому курьеру; чужой заказ — 404."""
    order = (
        Order.objects.filter(pk=order_id, delivery__courier=profile)
        .select_related("delivery", "shop", "client")
        .first()
    )
    if order is None:
        raise DeliveryError("not_found", "Заказ не найден", 404)
    return order


@transaction.atomic
def pickup_order(profile: CourierProfile, order_id: int) -> Order:
    """Забрал у магазина: courier_assigned → picked_up → on_the_way (старт трекинга)."""
    order = _courier_order(profile, order_id)
    if order.status != OrderStatus.COURIER_ASSIGNED:
        raise DeliveryError(
            "invalid_state", f"Заказ в статусе «{order.status}», забрать нельзя", 409
        )
    delivery = order.delivery
    delivery.picked_up_at = timezone.now()
    delivery.save(update_fields=["picked_up_at"])
    transition_order(order, OrderStatus.PICKED_UP, actor=profile.user)
    ws_events.notify_order_status(order)
    transition_order(order, OrderStatus.ON_THE_WAY, actor=profile.user)
    ws_events.notify_order_status(order)
    send_push(order.client, "order_status", {"order_id": order.id, "status": order.status})
    return order


@transaction.atomic
def arrive_order(profile: CourierProfile, order_id: int) -> Order:
    """На месте: on_the_way → arrived, клиенту push «курьер у двери»."""
    order = _courier_order(profile, order_id)
    if order.status != OrderStatus.ON_THE_WAY:
        raise DeliveryError(
            "invalid_state", f"Заказ в статусе «{order.status}», прибытие нельзя отметить", 409
        )
    delivery = order.delivery
    delivery.arrived_at = timezone.now()
    delivery.save(update_fields=["arrived_at"])
    transition_order(order, OrderStatus.ARRIVED, actor=profile.user)
    ws_events.notify_order_status(order)
    send_push(order.client, "courier_arrived", {"order_id": order.id})
    return order


@transaction.atomic
def complete_order(profile: CourierProfile, order_id: int, pin: str | None = None, photo=None) -> Order:
    """Завершение доставки: PIN получателя или фото → delivered.

    После delivered планируется complete_delivered_order (2 ч без спора →
    completed + расчёт с магазином), курьер снова на линии (online).
    """
    order = _courier_order(profile, order_id)
    if order.status != OrderStatus.ARRIVED:
        raise DeliveryError(
            "invalid_state", f"Заказ в статусе «{order.status}», завершить нельзя", 409
        )
    delivery = order.delivery
    if pin is not None:
        if pin != delivery.pin_code:
            raise DeliveryError("invalid_pin", "Неверный PIN-код получателя", 400)
        delivery.confirmation_type = Delivery.ConfirmationType.PIN
    elif photo is not None:
        delivery.confirmation_type = Delivery.ConfirmationType.PHOTO
        delivery.confirmation_photo = photo
    else:
        raise DeliveryError(
            "confirmation_required", "Нужен PIN-код или фото подтверждения", 400
        )
    delivery.delivered_at = timezone.now()
    delivery.save(
        update_fields=["confirmation_type", "confirmation_photo", "delivered_at"]
    )
    transition_order(order, OrderStatus.DELIVERED, actor=profile.user)

    profile.status = CourierProfile.Status.ONLINE
    profile.save(update_fields=["status"])

    from orders.tasks import DELIVERED_COMPLETE_TIMEOUT_SECONDS, complete_delivered_order

    complete_delivered_order.apply_async(
        (order.id,), countdown=DELIVERED_COMPLETE_TIMEOUT_SECONDS
    )
    ws_events.notify_order_status(order)
    send_push(order.client, "order_status", {"order_id": order.id, "status": order.status})
    return order


def submit_locations(profile: CourierProfile, points: list[dict]) -> dict:
    """Батч GPS-точек курьера (api.md §6).

    Принимается только при активной доставке picked_up..arrived.
    Живая позиция → Redis (courier:loc:{id}, TTL 60 сек) + WS клиенту;
    в CourierLocation пишем прореженно (не чаще 1 точки / 20 сек на доставку).
    """
    delivery = (
        Delivery.objects.filter(courier=profile, order__status__in=TRACKING_STATUSES)
        .select_related("order")
        .first()
    )
    if delivery is None:
        raise DeliveryError(
            "no_active_delivery",
            "Нет активной доставки в пути — геолокация не принимается",
            409,
        )

    saved = 0
    for point_data in points:
        lat, lng = point_data["lat"], point_data["lng"]
        recorded_at = datetime.fromtimestamp(point_data["ts"], tz=UTC)
        # живая позиция в Redis (TTL 60 сек)
        cache.set(
            f"courier:loc:{profile.id}",
            {"lat": lat, "lng": lng, "ts": point_data["ts"]},
            timeout=COURIER_LOC_CACHE_TTL_SECONDS,
        )
        # трансляция клиенту (пока picked_up..arrived — проверено выше)
        ws_events.notify_courier_location(delivery.order_id, lat, lng)
        # прореженная запись трека: cache.add атомарен — не чаще 1/20 сек
        if cache.add(
            f"courier:loc:save:{delivery.id}", 1, timeout=TRACK_SAVE_INTERVAL_SECONDS
        ):
            CourierLocation.objects.create(
                delivery=delivery,
                point=Point(lng, lat, srid=4326),
                recorded_at=recorded_at,
            )
            saved += 1

    last = points[-1]
    profile.current_point = Point(last["lng"], last["lat"], srid=4326)
    profile.save(update_fields=["current_point"])
    return {"accepted": len(points), "saved": saved}
