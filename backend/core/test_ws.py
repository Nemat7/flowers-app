"""Тесты WebSocket-каналов (api.md §7) через channels.testing.WebsocketCommunicator.

Channel layer — InMemoryChannelLayer (override_settings), JWT — как в проде
(query param ?token=<access>, core/middleware.py). События триггерятся через
реальные сервисы/API (database_sync_to_async — внутри ws_events async_to_sync).
"""
import uuid
from datetime import time, timedelta

from channels.db import database_sync_to_async
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.contrib.gis.geos import Point, Polygon
from django.test import TransactionTestCase, override_settings
from django.utils import timezone
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import User
from catalog.models import Category, Product, Shop, ShopStaff, ShopWorkingHours
from core import ws_events
from core.middleware import JWTQueryParamAuthMiddleware
from core.models import DeliveryZone
from core.routing import websocket_urlpatterns
from delivery.models import CourierProfile
from orders.models import Order
from orders.services import create_order, transition_order
from orders.state_machine import OrderStatus

# Душанбе, центр
LAT, LNG = 38.5598, 68.7870

TEST_CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}

# ASGI-приложение как в config/asgi.py (JWT middleware + роутинг)
test_application = JWTQueryParamAuthMiddleware(URLRouter(websocket_urlpatterns))


def _jwt(user) -> str:
    """Access-токен. Вызывать ТОЛЬКО из sync-контекста (setUp): simplejwt с
    blacklist пишет OutstandingToken в БД при создании токена."""
    return str(RefreshToken.for_user(user).access_token)


@override_settings(
    CHANNEL_LAYERS=TEST_CHANNEL_LAYERS,
    DEBUG=True,
    ALLOW_STUB_PAYMENTS=True,
    CELERY_TASK_ALWAYS_EAGER=False,
)
class WebSocketTests(TransactionTestCase):
    """WS: auth, права, события status_changed/new_order/order_available/courier_location."""

    def setUp(self):
        super().setUp()
        from unittest import mock

        # Celery-задачи не уходят в брокер из тестов
        patcher = mock.patch("celery.app.task.Task.apply_async", lambda *a, **kw: None)
        patcher.start()
        self.addCleanup(patcher.stop)

        self.zone = DeliveryZone.objects.create(
            name="Центр",
            polygon=Polygon(
                (
                    (68.74, 38.53), (68.84, 38.53), (68.84, 38.60), (68.74, 38.60),
                    (68.74, 38.53),
                ),
                srid=4326,
            ),
            base_price="10.00",
            price_per_km="2.00",
            min_order_amount="0.00",
        )
        self.shop = Shop.objects.create(
            name="Флора",
            point=Point(LNG, LAT, srid=4326),
            address_text="Рудаки 25",
            status=Shop.Status.APPROVED,
            commission_rate="15.00",
            min_order_amount="50.00",
        )
        self.shop.zones.add(self.zone)
        for weekday in range(7):
            ShopWorkingHours.objects.create(
                shop=self.shop, weekday=weekday,
                open_time=time(0, 0), close_time=time(23, 59),
            )
        self.category = Category.objects.create(name="Букеты", slug="bukety")
        self.product = Product.objects.create(
            shop=self.shop, category=self.category, name="Розы", price="350.00"
        )
        self.client_user = User.objects.create_user(phone="+992900000001")
        self.other_user = User.objects.create_user(phone="+992900000099")
        self.staff_user = User.objects.create_user(
            phone="+992900000002", role=User.Role.SHOP_STAFF
        )
        ShopStaff.objects.create(user=self.staff_user, shop=self.shop)
        self.courier_user = User.objects.create_user(
            phone="+992900000010", role=User.Role.COURIER
        )
        self.courier = CourierProfile.objects.create(
            user=self.courier_user,
            status=CourierProfile.Status.ONLINE,
            current_point=Point(LNG, LAT, srid=4326),
        )
        self.order = self._create_order()
        # токены создаём синхронно (simplejwt+blacklist пишет в БД)
        self.tokens = {
            user.id: _jwt(user)
            for user in (
                self.client_user, self.other_user, self.staff_user, self.courier_user,
            )
        }

    def _create_order(self) -> Order:
        order, _ = create_order(
            self.client_user,
            {
                "shop_id": self.shop.id,
                "items": [{"product_id": self.product.id, "qty": 1}],
                "recipient_name": "Гульчехра",
                "recipient_phone": "+992900000009",
                "address": {"lat": LAT, "lng": LNG, "address_text": "Рудаки 25"},
                "slot_type": "asap",
            },
        )
        return order

    def _client_ws(self, user=None, order_id=None):
        user = user or self.client_user
        return WebsocketCommunicator(
            test_application,
            f"/ws/client/orders/{order_id or self.order.id}/?token={self.tokens[user.id]}",
        )

    def _shop_ws(self, user=None):
        user = user or self.staff_user
        return WebsocketCommunicator(
            test_application, f"/ws/shop/?token={self.tokens[user.id]}"
        )

    def _courier_ws(self, user=None):
        user = user or self.courier_user
        return WebsocketCommunicator(
            test_application, f"/ws/courier/?token={self.tokens[user.id]}"
        )

    # --- auth и права ---

    async def test_invalid_token_rejected(self):
        communicator = WebsocketCommunicator(
            test_application, f"/ws/client/orders/{self.order.id}/?token=bad-token"
        )
        connected, close_code = await communicator.connect()
        self.assertFalse(connected)
        self.assertEqual(close_code, 4401)
        await communicator.disconnect()

    async def test_no_token_rejected(self):
        communicator = WebsocketCommunicator(
            test_application, f"/ws/client/orders/{self.order.id}/"
        )
        connected, close_code = await communicator.connect()
        self.assertFalse(connected)
        self.assertEqual(close_code, 4401)
        await communicator.disconnect()

    async def test_foreign_order_rejected(self):
        communicator = self._client_ws(user=self.other_user)
        connected, close_code = await communicator.connect()
        self.assertFalse(connected)
        self.assertEqual(close_code, 4403)
        await communicator.disconnect()

    async def test_shop_ws_forbidden_for_client(self):
        communicator = self._shop_ws(user=self.client_user)
        connected, close_code = await communicator.connect()
        self.assertFalse(connected)
        self.assertEqual(close_code, 4403)
        await communicator.disconnect()

    async def test_courier_ws_forbidden_for_client(self):
        communicator = self._courier_ws(user=self.client_user)
        connected, close_code = await communicator.connect()
        self.assertFalse(connected)
        self.assertEqual(close_code, 4403)
        await communicator.disconnect()

    # --- клиент: status_changed / courier_location ---

    async def test_client_receives_status_changed(self):
        communicator = self._client_ws()
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        @database_sync_to_async
        def mark_paid():
            transition_order(self.order, OrderStatus.PAID)
            ws_events.notify_order_status(self.order)

        await mark_paid()
        event = await communicator.receive_json_from(timeout=5)
        self.assertEqual(event["type"], "status_changed")
        self.assertEqual(event["status"], OrderStatus.PAID)
        self.assertEqual(event["order_id"], self.order.id)
        self.assertIn("at", event)
        await communicator.disconnect()

    async def test_client_receives_courier_location(self):
        communicator = self._client_ws()
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        await database_sync_to_async(ws_events.notify_courier_location)(
            self.order.id, LAT + 0.001, LNG + 0.001
        )
        event = await communicator.receive_json_from(timeout=5)
        self.assertEqual(event["type"], "courier_location")
        self.assertAlmostEqual(event["lat"], LAT + 0.001)
        self.assertAlmostEqual(event["lng"], LNG + 0.001)
        await communicator.disconnect()

    # --- магазин: new_order при оплате (полный путь через API) ---

    async def test_shop_receives_new_order_on_payment(self):
        communicator = self._shop_ws()
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        @database_sync_to_async
        def pay():
            from rest_framework.test import APIClient

            api = APIClient()
            api.force_authenticate(self.client_user)
            response = api.post(
                f"/api/v1/orders/{self.order.id}/pay/",
                {"provider": "stub"},
                format="json",
                HTTP_IDEMPOTENCY_KEY=str(uuid.uuid4()),
            )
            assert response.status_code == 201, response.data

        await pay()
        event = await communicator.receive_json_from(timeout=5)
        self.assertEqual(event["type"], "new_order")
        self.assertEqual(event["order_id"], self.order.id)
        self.assertEqual(event["number"], self.order.number)
        expires_at = timezone.datetime.fromisoformat(event["expires_at"])
        self.assertGreater(expires_at, timezone.now())
        self.assertLess(expires_at, timezone.now() + timedelta(minutes=6))
        await communicator.disconnect()

    # --- курьер: order_available / order_taken ---

    async def test_courier_receives_order_available_on_ready(self):
        communicator = self._courier_ws()
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        @database_sync_to_async
        def move_to_ready():
            self.order.refresh_from_db()
            for status in (
                OrderStatus.PAID, OrderStatus.SHOP_PENDING,
                OrderStatus.ACCEPTED, OrderStatus.PREPARING, OrderStatus.READY,
            ):
                transition_order(self.order, status)
            ws_events.notify_couriers_order_available(self.order)

        await move_to_ready()
        event = await communicator.receive_json_from(timeout=5)
        self.assertEqual(event["type"], "order_available")
        self.assertEqual(event["order_id"], self.order.id)
        self.assertEqual(event["shop"]["id"], self.shop.id)
        self.assertEqual(event["delivery_fee"], str(self.order.delivery_fee))
        # курьер стоит в точке магазина → дистанция ~0
        self.assertEqual(event["distance"], 0)
        await communicator.disconnect()

    async def test_courier_receives_order_taken(self):
        communicator = self._courier_ws()
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        await database_sync_to_async(ws_events.notify_couriers_order_taken)(self.order)
        event = await communicator.receive_json_from(timeout=5)
        self.assertEqual(event["type"], "order_taken")
        self.assertEqual(event["order_id"], self.order.id)
        await communicator.disconnect()
