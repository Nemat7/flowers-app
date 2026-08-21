"""WebSocket consumers (api.md §7).

  /ws/client/orders/{id}/  — статусы заказа + позиция курьера (владелец заказа)
  /ws/shop/                — входящие заказы и отмены (сотрудник магазина)
  /ws/courier/             — доступные заказы (курьер; группа couriers_online)

Auth — JWT в query (?token=<access>), см. core/middleware.py.
Отправка событий — core/ws_events.py.
"""
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer

COURIERS_ONLINE_GROUP = "couriers_online"


class _BaseConsumer(AsyncJsonWebsocketConsumer):
    """Общая логика: закрытие без аутентификации, отписка от групп."""

    groups: tuple[str, ...] = ()

    async def _user_or_close(self):
        user = self.scope.get("user")
        if user is None or not user.is_authenticated:
            await self.close(code=4401)
            return None
        return user

    async def disconnect(self, code):
        for group in self.groups:
            await self.channel_layer.group_discard(group, self.channel_name)


class ClientOrderConsumer(_BaseConsumer):
    """/ws/client/orders/{id}/ — только владелец заказа."""

    async def connect(self):
        user = await self._user_or_close()
        if user is None:
            return
        self.order_id = self.scope["url_route"]["kwargs"]["order_id"]
        if not await self._owns_order(user.id, self.order_id):
            await self.close(code=4403)
            return
        self.groups = (f"order_{self.order_id}",)
        await self.channel_layer.group_add(self.groups[0], self.channel_name)
        await self.accept()

    @database_sync_to_async
    def _owns_order(self, user_id, order_id) -> bool:
        from orders.models import Order

        return Order.objects.filter(pk=order_id, client_id=user_id).exists()

    # --- события (core/ws_events.py) ---

    async def status_changed(self, event):
        await self.send_json(
            {
                "type": "status_changed",
                "order_id": event["order_id"],
                "status": event["status"],
                "at": event["at"],
            }
        )

    async def courier_location(self, event):
        await self.send_json(
            {"type": "courier_location", "lat": event["lat"], "lng": event["lng"]}
        )

    async def bouquet_photo(self, event):
        await self.send_json(
            {
                "type": "bouquet_photo",
                "order_id": event["order_id"],
                "photo_url": event["photo_url"],
            }
        )


class ShopConsumer(_BaseConsumer):
    """/ws/shop/ — сотрудники магазина (скоуп — свой магазин из ShopStaff)."""

    async def connect(self):
        user = await self._user_or_close()
        if user is None:
            return
        shop_id = await self._staff_shop_id(user.id)
        if shop_id is None:
            await self.close(code=4403)
            return
        self.groups = (f"shop_{shop_id}",)
        await self.channel_layer.group_add(self.groups[0], self.channel_name)
        await self.accept()

    @database_sync_to_async
    def _staff_shop_id(self, user_id):
        from catalog.models import ShopStaff

        membership = ShopStaff.objects.filter(user_id=user_id).first()
        return membership.shop_id if membership else None

    async def new_order(self, event):
        await self.send_json(
            {
                "type": "new_order",
                "order_id": event["order_id"],
                "number": event["number"],
                "total": event["total"],
                "expires_at": event["expires_at"],
            }
        )

    async def order_cancelled(self, event):
        await self.send_json(
            {
                "type": "order_cancelled",
                "order_id": event["order_id"],
                "number": event["number"],
                "status": event["status"],
            }
        )

    async def photo_approved(self, event):
        await self.send_json(
            {
                "type": "photo_approved",
                "order_id": event["order_id"],
                "number": event["number"],
            }
        )

    async def photo_rejected(self, event):
        await self.send_json(
            {
                "type": "photo_rejected",
                "order_id": event["order_id"],
                "number": event["number"],
            }
        )


class CourierConsumer(_BaseConsumer):
    """/ws/courier/ — курьеры. Группа couriers_online: вход/выход по PATCH status
    (служебное событие set_online из core/ws_events.set_courier_online)."""

    async def connect(self):
        user = await self._user_or_close()
        if user is None:
            return
        profile_status = await self._courier_status(user.id)
        if profile_status is None:
            await self.close(code=4403)
            return
        self.personal_group = f"courier_{user.id}"
        self.groups = [self.personal_group]
        await self.channel_layer.group_add(self.personal_group, self.channel_name)
        self.is_online = profile_status != "offline"
        if self.is_online:
            await self.channel_layer.group_add(COURIERS_ONLINE_GROUP, self.channel_name)
            self.groups.append(COURIERS_ONLINE_GROUP)
        await self.accept()

    @database_sync_to_async
    def _courier_status(self, user_id):
        from delivery.models import CourierProfile

        profile = CourierProfile.objects.filter(user_id=user_id).first()
        return profile.status if profile else None

    async def set_online(self, event):
        """Вход/выход из couriers_online по PATCH /courier/status/."""
        online = event["online"]
        if online and not self.is_online:
            await self.channel_layer.group_add(COURIERS_ONLINE_GROUP, self.channel_name)
            self.groups.append(COURIERS_ONLINE_GROUP)
        elif not online and self.is_online:
            await self.channel_layer.group_discard(COURIERS_ONLINE_GROUP, self.channel_name)
            self.groups.remove(COURIERS_ONLINE_GROUP)
        self.is_online = online

    async def order_available(self, event):
        await self.send_json(
            {
                "type": "order_available",
                "order_id": event["order_id"],
                "shop": event["shop"],
                "delivery_fee": event["delivery_fee"],
                "distance": event["distance"],
            }
        )

    async def order_taken(self, event):
        await self.send_json({"type": "order_taken", "order_id": event["order_id"]})
