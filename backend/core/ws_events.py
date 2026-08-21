"""Отправка WebSocket-событий в группы каналов (api.md §7).

Группы каналов:
  order_{id}        — клиент-владелец заказа (статусы, позиция курьера)
  shop_{id}         — сотрудники магазина (новые заказы, отмены)
  couriers_online   — онлайн-курьеры (order_taken и др. широковещательное)
  courier_{user_id} — персональный канал курьера (order_available с дистанцией,
                      служебный set_online для входа/выхода из couriers_online)

Вызывается из sync-кода (views/services/tasks). Сбой отправки не должен
ломать основной поток — ошибки логируются.
"""
import logging
from math import asin, cos, radians, sin, sqrt

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.utils import timezone

logger = logging.getLogger(__name__)


def group_send_sync(group: str, message: dict) -> None:
    """group_send из sync-кода; ошибки логируются, но не пробрасываются."""
    try:
        layer = get_channel_layer()
        if layer is None:
            return
        async_to_sync(layer.group_send)(group, message)
    except Exception:
        logger.exception("WS group_send не удался: group=%s type=%s", group, message.get("type"))


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> int:
    """Дистанция между точками в метрах (для поля distance курьерам)."""
    r = 6_371_000
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng / 2) ** 2
    return round(2 * r * asin(sqrt(a)))


# --- клиент: заказ ---

def notify_order_status(order) -> None:
    """status_changed {status, at} владельцу заказа."""
    group_send_sync(
        f"order_{order.id}",
        {
            "type": "status_changed",
            "order_id": order.id,
            "status": order.status,
            "at": timezone.now().isoformat(),
        },
    )


def notify_courier_location(order_id: int, lat: float, lng: float) -> None:
    """courier_location {lat, lng} — живой трек курьера для клиента."""
    group_send_sync(
        f"order_{order_id}",
        {"type": "courier_location", "lat": lat, "lng": lng},
    )


def notify_bouquet_photo(order, photo_url: str) -> None:
    """bouquet_photo {photo_url} — магазин прислал фото собранного букета."""
    group_send_sync(
        f"order_{order.id}",
        {
            "type": "bouquet_photo",
            "order_id": order.id,
            "photo_url": photo_url,
        },
    )


def notify_shop_photo_response(order, approved: bool) -> None:
    """photo_approved / photo_rejected — клиент ответил на фото букета."""
    group_send_sync(
        f"shop_{order.shop_id}",
        {
            "type": "photo_approved" if approved else "photo_rejected",
            "order_id": order.id,
            "number": order.number,
        },
    )


# --- магазин ---

def notify_shop_new_order(order, expires_at) -> None:
    """new_order {order_id, number, total, expires_at} сотрудникам магазина."""
    group_send_sync(
        f"shop_{order.shop_id}",
        {
            "type": "new_order",
            "order_id": order.id,
            "number": order.number,
            "total": str(order.total),
            "expires_at": expires_at.isoformat(),
        },
    )


def notify_shop_order_cancelled(order) -> None:
    """order_cancelled — заказ ушёл из очереди магазина (отмена/таймаут)."""
    group_send_sync(
        f"shop_{order.shop_id}",
        {
            "type": "order_cancelled",
            "order_id": order.id,
            "number": order.number,
            "status": order.status,
        },
    )


# --- курьеры ---

def notify_couriers_order_available(order) -> None:
    """order_available {order_id, shop, delivery_fee, distance} онлайн-курьерам.

    Назначение в MVP: push всем онлайн-курьерам, кто первый принял — тот везёт
    (business-logic.md §6). distance считается от последней позиции курьера
    (CourierProfile.current_point), поэтому событие уходит в персональные
    каналы courier_{user_id}.
    """
    from delivery.models import CourierProfile

    shop = order.shop
    shop_payload = {
        "id": shop.id,
        "name": shop.name,
        "address_text": shop.address_text,
        "lat": shop.point.y if shop.point else None,
        "lng": shop.point.x if shop.point else None,
    }
    couriers = CourierProfile.objects.filter(
        status=CourierProfile.Status.ONLINE
    ).select_related("user")
    for courier in couriers:
        distance = None
        if courier.current_point and shop.point:
            distance = _haversine_m(
                courier.current_point.y, courier.current_point.x,
                shop.point.y, shop.point.x,
            )
        group_send_sync(
            f"courier_{courier.user_id}",
            {
                "type": "order_available",
                "order_id": order.id,
                "shop": shop_payload,
                "delivery_fee": str(order.delivery_fee),
                "distance": distance,
            },
        )


def notify_couriers_order_taken(order) -> None:
    """order_taken — заказ ушёл другому курьеру (широковещательно)."""
    group_send_sync(
        "couriers_online",
        {"type": "order_taken", "order_id": order.id},
    )


def set_courier_online(user_id: int, online: bool) -> None:
    """Служебное событие: войти/выйти из группы couriers_online (PATCH status)."""
    group_send_sync(
        f"courier_{user_id}",
        {"type": "set_online", "online": online},
    )
