"""Тесты API курьера (api.md §6): линия, приём заказа, доставка, трекинг, заработок."""
import base64
import time
from decimal import Decimal
from unittest import mock

from django.contrib.gis.geos import Point
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings

from accounts.models import User
from delivery.models import CourierLocation, CourierProfile
from delivery.services import TRACK_SAVE_INTERVAL_SECONDS
from orders.state_machine import OrderStatus
from orders.tasks import DELIVERED_COMPLETE_TIMEOUT_SECONDS
from orders.tests import BaseFlowersTestCase, LAT, LNG

COURIER_URL = "/api/v1/courier/"

# 1x1 PNG для multipart-фото подтверждения
PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
    "+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)

TEST_CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": "redis://redis:6379/15",  # изолированная БД Redis для тестов
        "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},
    }
}


@override_settings(ALLOW_STUB_PAYMENTS=True)
class BaseCourierTestCase(BaseFlowersTestCase):
    """Фикстура BaseFlowersTestCase + два курьера (online, позиция в центре)."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.courier_user = User.objects.create_user(
            phone="+992900000010", role=User.Role.COURIER
        )
        cls.courier = CourierProfile.objects.create(
            user=cls.courier_user,
            status=CourierProfile.Status.ONLINE,
            current_point=Point(LNG, LAT, srid=4326),
        )
        cls.courier2_user = User.objects.create_user(
            phone="+992900000011", role=User.Role.COURIER
        )
        cls.courier2 = CourierProfile.objects.create(
            user=cls.courier2_user, status=CourierProfile.Status.ONLINE
        )

    def setUp(self):
        super().setUp()
        self.as_courier()

    def as_courier(self, user=None):
        self.api.force_authenticate(user or self.courier_user)

    def ready_order(self):
        """Оплаченный заказ, доведённый магазином до ready."""
        order = self.create_order()
        self.pay_order(order)
        self.as_staff()
        self.api.post(
            f"/api/v1/shop/orders/{order.id}/accept/", {"eta_minutes": 15}, format="json"
        )
        self.api.post(f"/api/v1/shop/orders/{order.id}/ready/", {}, format="json")
        self.as_courier()
        order.refresh_from_db()
        assert order.status == OrderStatus.READY
        return order

    def accept(self, order):
        return self.api.post(f"{COURIER_URL}orders/{order.id}/accept/", {}, format="json")

    def assigned_order(self):
        order = self.ready_order()
        response = self.accept(order)
        assert response.status_code == 200, response.data
        order.refresh_from_db()
        return order

    def delivered_order(self):
        """Заказ, доведённый курьером до arrived (готов к complete)."""
        order = self.assigned_order()
        self.api.post(f"{COURIER_URL}orders/{order.id}/pickup/", {}, format="json")
        self.api.post(f"{COURIER_URL}orders/{order.id}/arrive/", {}, format="json")
        order.refresh_from_db()
        assert order.status == OrderStatus.ARRIVED
        return order


class CourierStatusTests(BaseCourierTestCase):
    def test_get_status(self):
        response = self.api.get(f"{COURIER_URL}status/")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], CourierProfile.Status.ONLINE)

        self.courier.status = CourierProfile.Status.OFFLINE
        self.courier.save(update_fields=["status"])
        response = self.api.get(f"{COURIER_URL}status/")
        self.assertEqual(response.data["status"], "offline")

    def test_get_status_client_forbidden(self):
        self.api.force_authenticate(self.client_user)
        response = self.api.get(f"{COURIER_URL}status/")
        self.assertEqual(response.status_code, 403)

    def test_online_offline(self):
        response = self.api.patch(f"{COURIER_URL}status/", {"status": "offline"}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "offline")
        self.courier.refresh_from_db()
        self.assertEqual(self.courier.status, CourierProfile.Status.OFFLINE)

        response = self.api.patch(f"{COURIER_URL}status/", {"status": "online"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.courier.refresh_from_db()
        self.assertEqual(self.courier.status, CourierProfile.Status.ONLINE)

    def test_offline_forbidden_with_active_order(self):
        self.assigned_order()
        response = self.api.patch(f"{COURIER_URL}status/", {"status": "offline"}, format="json")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "active_delivery")
        self.courier.refresh_from_db()
        self.assertEqual(self.courier.status, CourierProfile.Status.BUSY)

    def test_invalid_status_value(self):
        response = self.api.patch(f"{COURIER_URL}status/", {"status": "busy"}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_client_forbidden(self):
        self.api.force_authenticate(self.client_user)
        response = self.api.patch(f"{COURIER_URL}status/", {"status": "online"}, format="json")
        self.assertEqual(response.status_code, 403)


class CourierAvailableCurrentTests(BaseCourierTestCase):
    def test_available_lists_ready_without_courier(self):
        order = self.ready_order()
        response = self.api.get(f"{COURIER_URL}orders/available/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        item = response.data[0]
        self.assertEqual(item["id"], order.id)
        self.assertEqual(item["shop"]["id"], self.shop.id)
        self.assertEqual(Decimal(item["delivery_fee"]), order.delivery_fee)
        # курьер стоит в точке магазина → дистанция ~0
        self.assertEqual(item["distance"], 0)

    def test_available_hides_non_ready(self):
        order = self.create_order()  # created, не ready
        self.pay_order(order)  # shop_pending, не ready
        response = self.api.get(f"{COURIER_URL}orders/available/")
        self.assertEqual(response.data, [])

    def test_current_order_empty_then_active(self):
        response = self.api.get(f"{COURIER_URL}orders/current/")
        self.assertEqual(response.data, {"order": None})

        order = self.assigned_order()
        response = self.api.get(f"{COURIER_URL}orders/current/")
        self.assertEqual(response.data["order"]["id"], order.id)
        self.assertEqual(response.data["order"]["status"], OrderStatus.COURIER_ASSIGNED)
        self.assertEqual(
            Decimal(response.data["order"]["fee"]), order.delivery_fee
        )
        self.assertEqual(response.data["order"]["address"]["lat"], LAT)


class CourierAcceptTests(BaseCourierTestCase):
    def test_accept_success(self):
        order = self.ready_order()
        response = self.accept(order)
        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.COURIER_ASSIGNED)
        delivery = order.delivery
        self.assertEqual(delivery.courier, self.courier)
        self.assertEqual(delivery.fee, order.delivery_fee)
        self.assertIsNotNone(delivery.assigned_at)
        self.courier.refresh_from_db()
        self.assertEqual(self.courier.status, CourierProfile.Status.BUSY)
        self.assertTrue(
            order.status_history.filter(status=OrderStatus.COURIER_ASSIGNED).exists()
        )

    def test_accept_race_second_courier_gets_409(self):
        order = self.ready_order()
        first = self.accept(order)
        self.assertEqual(first.status_code, 200)
        self.as_courier(self.courier2_user)
        second = self.accept(order)
        self.assertEqual(second.status_code, 409)
        self.assertEqual(second.data["error"]["code"], "order_taken")

    def test_accept_offline_rejected(self):
        self.courier.status = CourierProfile.Status.OFFLINE
        self.courier.save(update_fields=["status"])
        order = self.ready_order()
        response = self.accept(order)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "courier_offline")

    def test_accept_with_active_order_conflict(self):
        self.assigned_order()
        second_order = self.ready_order()
        response = self.accept(second_order)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "active_delivery")

    def test_accept_not_ready_conflict(self):
        order = self.create_order()
        self.pay_order(order)  # shop_pending
        response = self.accept(order)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "invalid_state")

    def test_client_cannot_accept(self):
        order = self.ready_order()
        self.api.force_authenticate(self.client_user)
        response = self.accept(order)
        self.assertEqual(response.status_code, 403)


class CourierFlowTests(BaseCourierTestCase):
    def test_pickup_moves_to_on_the_way(self):
        order = self.assigned_order()
        response = self.api.post(f"{COURIER_URL}orders/{order.id}/pickup/", {}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.ON_THE_WAY)
        self.assertIsNotNone(order.delivery.picked_up_at)
        statuses = list(
            order.status_history.order_by("id").values_list("status", flat=True)
        )
        self.assertIn(OrderStatus.PICKED_UP, statuses)
        self.assertIn(OrderStatus.ON_THE_WAY, statuses)

    def test_arrive(self):
        order = self.assigned_order()
        self.api.post(f"{COURIER_URL}orders/{order.id}/pickup/", {}, format="json")
        response = self.api.post(f"{COURIER_URL}orders/{order.id}/arrive/", {}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.ARRIVED)
        self.assertIsNotNone(order.delivery.arrived_at)

    def test_complete_with_pin(self):
        order = self.delivered_order()
        pin = order.delivery.pin_code
        with mock.patch("celery.app.task.Task.apply_async") as mocked:
            response = self.api.post(
                f"{COURIER_URL}orders/{order.id}/complete/", {"pin": pin}, format="json"
            )
        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.DELIVERED)
        delivery = order.delivery
        self.assertEqual(delivery.confirmation_type, "pin")
        self.assertIsNotNone(delivery.delivered_at)
        # курьер снова на линии
        self.courier.refresh_from_db()
        self.assertEqual(self.courier.status, CourierProfile.Status.ONLINE)
        # запланировано авто-завершение через 2 часа
        mocked.assert_called_once_with(
            (order.id,), countdown=DELIVERED_COMPLETE_TIMEOUT_SECONDS
        )

    def test_complete_wrong_pin(self):
        order = self.delivered_order()
        wrong = "9999" if order.delivery.pin_code != "9999" else "0000"
        response = self.api.post(
            f"{COURIER_URL}orders/{order.id}/complete/", {"pin": wrong}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "invalid_pin")
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.ARRIVED)

    def test_complete_with_photo(self):
        order = self.delivered_order()
        photo = SimpleUploadedFile("proof.png", PNG_BYTES, content_type="image/png")
        response = self.api.post(f"{COURIER_URL}orders/{order.id}/complete/", {"photo": photo})
        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.DELIVERED)
        self.assertEqual(order.delivery.confirmation_type, "photo")
        self.assertTrue(order.delivery.confirmation_photo)

    def test_complete_requires_pin_or_photo(self):
        order = self.delivered_order()
        response = self.api.post(f"{COURIER_URL}orders/{order.id}/complete/", {}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "confirmation_required")

    def test_complete_wrong_state_conflict(self):
        order = self.assigned_order()  # courier_assigned, ещё не arrived
        response = self.api.post(
            f"{COURIER_URL}orders/{order.id}/complete/",
            {"pin": order.delivery.pin_code},
            format="json",
        )
        self.assertEqual(response.status_code, 409)

    def test_foreign_courier_cannot_touch_order(self):
        order = self.assigned_order()  # назначен courier1
        self.as_courier(self.courier2_user)
        for action in ("pickup", "arrive", "complete"):
            response = self.api.post(
                f"{COURIER_URL}orders/{order.id}/{action}/", {}, format="json"
            )
            self.assertEqual(response.status_code, 404, action)

    def test_wrong_state_pickup_arrive_conflict(self):
        order = self.ready_order()  # не назначен этому курьеру → 404
        response = self.api.post(f"{COURIER_URL}orders/{order.id}/pickup/", {}, format="json")
        self.assertEqual(response.status_code, 404)

        order = self.assigned_order()
        response = self.api.post(f"{COURIER_URL}orders/{order.id}/arrive/", {}, format="json")
        self.assertEqual(response.status_code, 409)  # ещё не on_the_way


@override_settings(CACHES=TEST_CACHES)
class CourierLocationTests(BaseCourierTestCase):
    def setUp(self):
        super().setUp()
        cache.clear()  # изолированная БД Redis (15) — безопасно

    def _points(self, n=3, step_seconds=5):
        now = time.time()
        return [
            {"lat": LAT + i * 0.0001, "lng": LNG + i * 0.0001, "ts": now + i * step_seconds}
            for i in range(n)
        ]

    def test_location_requires_active_delivery(self):
        response = self.api.post(
            f"{COURIER_URL}location/", {"points": self._points()}, format="json"
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "no_active_delivery")

    def test_location_redis_and_throttled_db_write(self):
        order = self.assigned_order()
        self.api.post(f"{COURIER_URL}orders/{order.id}/pickup/", {}, format="json")
        delivery_id = order.delivery.id

        response = self.api.post(
            f"{COURIER_URL}location/", {"points": self._points(3)}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data, {"accepted": 3, "saved": 1})

        # живая позиция в Redis — последняя точка
        cached = cache.get(f"courier:loc:{self.courier.id}")
        self.assertIsNotNone(cached)
        last = self._points(3)[-1]
        self.assertAlmostEqual(cached["lat"], last["lat"])
        self.assertAlmostEqual(cached["lng"], last["lng"])

        # в БД — прорежено: 1 точка на доставку за окно 20 сек
        self.assertEqual(CourierLocation.objects.filter(delivery_id=delivery_id).count(), 1)

        # повторный батч в том же 20-секундном окне — без новых записей
        response = self.api.post(
            f"{COURIER_URL}location/", {"points": self._points(2)}, format="json"
        )
        self.assertEqual(response.data, {"accepted": 2, "saved": 0})
        self.assertEqual(CourierLocation.objects.filter(delivery_id=delivery_id).count(), 1)

        # окно истекло — следующая точка записывается
        cache.delete(f"courier:loc:save:{delivery_id}")
        response = self.api.post(
            f"{COURIER_URL}location/", {"points": self._points(1)}, format="json"
        )
        self.assertEqual(response.data, {"accepted": 1, "saved": 1})
        self.assertEqual(CourierLocation.objects.filter(delivery_id=delivery_id).count(), 2)

        # current_point курьера — последняя принятая точка
        self.courier.refresh_from_db()
        expected = self._points(1)[0]
        self.assertAlmostEqual(self.courier.current_point.y, expected["lat"])
        self.assertAlmostEqual(self.courier.current_point.x, expected["lng"])

    def test_location_not_accepted_before_pickup(self):
        order = self.assigned_order()  # courier_assigned — трекинг ещё не стартовал
        response = self.api.post(
            f"{COURIER_URL}location/", {"points": self._points()}, format="json"
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "no_active_delivery")

    def test_location_validation(self):
        order = self.assigned_order()
        self.api.post(f"{COURIER_URL}orders/{order.id}/pickup/", {}, format="json")
        response = self.api.post(
            f"{COURIER_URL}location/",
            {"points": [{"lat": 95, "lng": LNG, "ts": time.time()}]},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        response = self.api.post(f"{COURIER_URL}location/", {"points": []}, format="json")
        self.assertEqual(response.status_code, 400)


class CourierEarningsHistoryTests(BaseCourierTestCase):
    def test_earnings_after_delivery(self):
        order = self.delivered_order()
        self.api.post(
            f"{COURIER_URL}orders/{order.id}/complete/",
            {"pin": order.delivery.pin_code},
            format="json",
        )
        response = self.api.get(f"{COURIER_URL}earnings/")
        self.assertEqual(response.status_code, 200)
        expected = str(order.delivery_fee)
        self.assertEqual(response.data["today"], expected)
        self.assertEqual(response.data["week"], expected)
        self.assertEqual(response.data["total"], expected)

    def test_earnings_zero_before_deliveries(self):
        response = self.api.get(f"{COURIER_URL}earnings/")
        self.assertEqual(response.data["today"], "0.00")
        self.assertEqual(response.data["total"], "0.00")

    def test_history_lists_finished_deliveries(self):
        order = self.delivered_order()
        self.api.post(
            f"{COURIER_URL}orders/{order.id}/complete/",
            {"pin": order.delivery.pin_code},
            format="json",
        )
        response = self.api.get(f"{COURIER_URL}orders/history/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 1)
        item = response.data["results"][0]
        self.assertEqual(item["id"], order.id)
        self.assertIsNotNone(item["delivered_at"])

        # активный заказ в историю не попадает
        self.assigned_order()
        response = self.api.get(f"{COURIER_URL}orders/history/")
        self.assertEqual(response.data["count"], 1)
