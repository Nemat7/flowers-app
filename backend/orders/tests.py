"""Тесты API заказов и платежей (api.md §3–§5, §9; business-logic.md §3, §7)."""
import shutil
import tempfile
import uuid
from datetime import time, timedelta
from decimal import Decimal
from unittest import mock

from django.contrib.gis.geos import Point, Polygon
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product, Shop, ShopStaff, ShopWorkingHours
from core.models import DeliveryZone
from marketing.models import PromoCode, PromoCodeUse
from orders.models import Order, OrderPhoto, OrderStatusHistory
from orders.services import transition_order
from orders.state_machine import OrderStatus
from orders.tasks import expire_unpaid_order, shop_response_timeout
from payments.models import Payment, Refund

# Душанбе, центр
LAT, LNG = 38.5598, 68.7870

ORDER_URL = "/api/v1/orders/"


def _polygon_around_center():
    return Polygon(
        (
            (68.74, 38.53), (68.84, 38.53), (68.84, 38.60), (68.74, 38.60),
            (68.74, 38.53),
        ),
        srid=4326,
    )


class BaseFlowersTestCase(TestCase):
    """Общая фикстура: зона, магазин, товары, клиент, сотрудник."""

    @classmethod
    def setUpTestData(cls):
        cls.zone = DeliveryZone.objects.create(
            name="Центр",
            polygon=_polygon_around_center(),
            base_price="10.00",
            price_per_km="2.00",
            min_order_amount="0.00",
        )
        cls.shop = Shop.objects.create(
            name="Флора",
            point=Point(LNG, LAT, srid=4326),
            address_text="Рудаки 25",
            status=Shop.Status.APPROVED,
            commission_rate="15.00",
            min_order_amount="50.00",
            card_price="5.00",
        )
        cls.shop.zones.add(cls.zone)
        cls.other_shop = Shop.objects.create(
            name="Другой магазин",
            point=Point(68.80, 38.57, srid=4326),
            address_text="Сомони 1",
            status=Shop.Status.APPROVED,
        )
        cls.other_shop.zones.add(cls.zone)
        for weekday in range(7):
            ShopWorkingHours.objects.create(
                shop=cls.shop, weekday=weekday,
                open_time=time(0, 0), close_time=time(23, 59),
            )
            ShopWorkingHours.objects.create(
                shop=cls.other_shop, weekday=weekday,
                open_time=time(0, 0), close_time=time(23, 59),
            )
        cls.category = Category.objects.create(name="Букеты", slug="bukety")
        cls.product = Product.objects.create(
            shop=cls.shop, category=cls.category, name="Розы", price="350.00"
        )
        cls.product2 = Product.objects.create(
            shop=cls.shop, category=cls.category, name="Тюльпаны", price="180.00"
        )
        cls.foreign_product = Product.objects.create(
            shop=cls.other_shop, category=cls.category, name="Чужой", price="100.00"
        )
        cls.promo = PromoCode.objects.create(
            code="SPRING10",
            type=PromoCode.Type.PERCENT,
            value="10.00",
            min_order_amount="100.00",
            valid_from=timezone.now() - timedelta(days=1),
            valid_to=timezone.now() + timedelta(days=30),
            per_user_limit=1,
        )
        cls.client_user = User.objects.create_user(phone="+992900000001")
        cls.staff_user = User.objects.create_user(
            phone="+992900000002", role=User.Role.SHOP_STAFF
        )
        ShopStaff.objects.create(user=cls.staff_user, shop=cls.shop)
        cls.other_staff = User.objects.create_user(
            phone="+992900000003", role=User.Role.SHOP_STAFF
        )
        ShopStaff.objects.create(user=cls.other_staff, shop=cls.other_shop)

    def setUp(self):
        self.api = APIClient()
        self.api.force_authenticate(self.client_user)
        # Celery-задачи не уходят в брокер из тестов
        patcher = mock.patch("celery.app.task.Task.apply_async", lambda *a, **kw: None)
        patcher.start()
        self.addCleanup(patcher.stop)

    # --- помощники ---

    def order_payload(self, **overrides):
        payload = {
            "shop_id": self.shop.id,
            "items": [{"product_id": self.product.id, "qty": 1}],
            "recipient_name": "Гульчехра",
            "recipient_phone": "+992900000009",
            "address": {
                "lat": LAT, "lng": LNG, "address_text": "Рудаки 25",
            },
            "slot_type": "asap",
        }
        payload.update(overrides)
        return payload

    def create_order(self, **overrides):
        response = self.api.post(ORDER_URL, self.order_payload(**overrides), format="json")
        assert response.status_code == 201, response.data
        return Order.objects.get(pk=response.data["id"])

    def pay_order(self, order, key=None):
        response = self.api.post(
            f"{ORDER_URL}{order.id}/pay/",
            {"provider": "stub"},
            format="json",
            HTTP_IDEMPOTENCY_KEY=str(key or uuid.uuid4()),
        )
        order.refresh_from_db()
        return response

    def as_staff(self, user=None):
        self.api.force_authenticate(user or self.staff_user)


@override_settings(ALLOW_STUB_PAYMENTS=True)
class OrderCreateTests(BaseFlowersTestCase):
    def test_create_success(self):
        response = self.api.post(
            ORDER_URL,
            self.order_payload(
                items=[
                    {"product_id": self.product.id, "qty": 1},
                    {"product_id": self.product2.id, "qty": 1},
                ],
                promo_code="SPRING10",
            ),
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        order = Order.objects.get(pk=response.data["id"])
        # серверный расчёт: subtotal 530, доставка 10 (точка = точка магазина),
        # скидка 10% от 530 = 53
        self.assertEqual(order.subtotal, Decimal("530.00"))
        self.assertEqual(order.delivery_fee, Decimal("10.00"))
        self.assertEqual(order.discount, Decimal("53.00"))
        self.assertEqual(order.total, Decimal("487.00"))
        self.assertRegex(order.number, r"^F-\d{6}$")
        self.assertEqual(order.items.count(), 2)
        # PIN доставки сгенерирован при создании, курьера нет
        self.assertEqual(len(order.delivery.pin_code), 4)
        self.assertIsNone(order.delivery.courier)
        # снимки цен
        item = order.items.get(product=self.product)
        self.assertEqual(item.price, Decimal("350.00"))
        self.assertEqual(item.product_name, "Розы")
        # промокод учтён
        self.promo.refresh_from_db()
        self.assertEqual(self.promo.uses_count, 1)

    def test_card_text_adds_card_price(self):
        order = self.create_order(card_text="С днём рождения!")
        self.assertEqual(order.card_price, Decimal("5.00"))
        self.assertEqual(order.subtotal, Decimal("355.00"))

    def test_product_from_another_shop_rejected(self):
        response = self.api.post(
            ORDER_URL,
            self.order_payload(
                items=[
                    {"product_id": self.product.id, "qty": 1},
                    {"product_id": self.foreign_product.id, "qty": 1},
                ]
            ),
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "different_shops")

    def test_shop_closed_rejected(self):
        ShopWorkingHours.objects.filter(shop=self.shop).update(is_day_off=True)
        response = self.api.post(ORDER_URL, self.order_payload(), format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "shop_closed")

    def test_scheduled_slot_ok(self):
        scheduled = timezone.now() + timedelta(hours=3)
        order = self.create_order(
            slot_type="scheduled", scheduled_at=scheduled.isoformat()
        )
        self.assertEqual(order.slot_type, "scheduled")
        self.assertIsNotNone(order.scheduled_at)

    def test_out_of_zone_rejected(self):
        response = self.api.post(
            ORDER_URL,
            self.order_payload(
                address={"lat": 38.0, "lng": 68.0, "address_text": "Далеко"}
            ),
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "out_of_zone")

    def test_min_order_rejected(self):
        cheap = Product.objects.create(
            shop=self.shop, category=self.category, name="Открытка", price="10.00"
        )
        response = self.api.post(
            ORDER_URL,
            self.order_payload(items=[{"product_id": cheap.id, "qty": 1}]),
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "min_order")

    def test_promo_min_order_rejected(self):
        cheap = Product.objects.create(
            shop=self.shop, category=self.category, name="Малый букет", price="60.00"
        )
        response = self.api.post(
            ORDER_URL,
            self.order_payload(
                items=[{"product_id": cheap.id, "qty": 1}], promo_code="SPRING10"
            ),
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "promo_invalid")

    def test_expired_promo_rejected(self):
        self.promo.valid_to = timezone.now() - timedelta(hours=1)
        self.promo.save(update_fields=["valid_to"])
        response = self.api.post(
            ORDER_URL, self.order_payload(promo_code="SPRING10"), format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "promo_invalid")

    def test_promo_per_user_limit(self):
        self.create_order(promo_code="SPRING10")
        response = self.api.post(
            ORDER_URL, self.order_payload(promo_code="SPRING10"), format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "promo_invalid")

    def test_idempotent_creation(self):
        key = str(uuid.uuid4())
        r1 = self.api.post(
            ORDER_URL, self.order_payload(), format="json", HTTP_IDEMPOTENCY_KEY=key
        )
        r2 = self.api.post(
            ORDER_URL, self.order_payload(), format="json", HTTP_IDEMPOTENCY_KEY=key
        )
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(r1.data["id"], r2.data["id"])
        self.assertEqual(Order.objects.count(), 1)


@override_settings(ALLOW_STUB_PAYMENTS=True)
class PaymentTests(BaseFlowersTestCase):
    def test_stub_pay_success(self):
        order = self.create_order()
        response = self.pay_order(order)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], "success")
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.SHOP_PENDING)
        payment = order.payments.get()
        self.assertEqual(payment.status, Payment.Status.SUCCESS)
        self.assertEqual(payment.amount, order.total)
        # оба перехода записаны в историю
        statuses = list(
            order.status_history.order_by("id").values_list("status", flat=True)
        )
        self.assertEqual(
            statuses,
            [OrderStatus.CREATED, OrderStatus.PAID, OrderStatus.SHOP_PENDING],
        )

    def test_pay_idempotency(self):
        order = self.create_order()
        key = uuid.uuid4()
        r1 = self.pay_order(order, key)
        r2 = self.pay_order(order, key)
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(r1.data["payment_id"], r2.data["payment_id"])
        self.assertEqual(Payment.objects.count(), 1)

    def test_pay_without_key_rejected(self):
        order = self.create_order()
        response = self.api.post(
            f"{ORDER_URL}{order.id}/pay/", {"provider": "stub"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "idempotency_key_required")

    def test_pay_already_paid_conflict(self):
        order = self.create_order()
        self.pay_order(order)
        response = self.pay_order(order)  # новый ключ
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "invalid_state")

    @override_settings(ALLOW_STUB_PAYMENTS=False, DEBUG=False)
    def test_stub_disabled_in_prod(self):
        order = self.create_order()
        response = self.pay_order(order)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data["error"]["code"], "stub_disabled")


@override_settings(ALLOW_STUB_PAYMENTS=True)
class OrderCancelTests(BaseFlowersTestCase):
    def test_cancel_created_no_refund(self):
        order = self.create_order(promo_code="SPRING10")
        response = self.api.post(f"{ORDER_URL}{order.id}/cancel/", {}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.CANCELLED_CLIENT)
        self.assertIsNone(response.data["refund_amount"])
        # промокод освобождён
        self.assertFalse(PromoCodeUse.objects.filter(order=order).exists())
        self.promo.refresh_from_db()
        self.assertEqual(self.promo.uses_count, 0)

    def test_cancel_paid_full_refund(self):
        order = self.create_order()
        self.pay_order(order)
        response = self.api.post(f"{ORDER_URL}{order.id}/cancel/", {}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(Decimal(response.data["refund_amount"]), order.total)
        payment = order.payments.get()
        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.REFUNDED)
        refund = Refund.objects.get(payment=payment)
        self.assertEqual(refund.amount, order.total)

    def test_cancel_after_accept_retention(self):
        order = self.create_order()
        self.pay_order(order)
        transition_order(order, OrderStatus.ACCEPTED)
        transition_order(order, OrderStatus.PREPARING)
        response = self.api.post(f"{ORDER_URL}{order.id}/cancel/", {}, format="json")
        self.assertEqual(response.status_code, 200)
        # удержание 10% (CANCEL_RETENTION_PREPARING_PERCENT)
        expected = (order.total * Decimal("0.9")).quantize(Decimal("0.01"))
        self.assertEqual(Decimal(response.data["refund_amount"]), expected)
        payment = order.payments.get()
        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.PARTIALLY_REFUNDED)

    def test_cancel_ready_retention_20(self):
        order = self.create_order()
        self.pay_order(order)
        transition_order(order, OrderStatus.ACCEPTED)
        transition_order(order, OrderStatus.PREPARING)
        transition_order(order, OrderStatus.READY)
        response = self.api.post(f"{ORDER_URL}{order.id}/cancel/", {}, format="json")
        self.assertEqual(response.status_code, 200)
        # удержание 20% (CANCEL_RETENTION_READY_PERCENT)
        expected = (order.total * Decimal("0.8")).quantize(Decimal("0.01"))
        self.assertEqual(Decimal(response.data["refund_amount"]), expected)
        payment = order.payments.get()
        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.PARTIALLY_REFUNDED)
        refund = Refund.objects.get(payment=payment)
        self.assertEqual(refund.amount, expected)

    def test_cancel_after_pickup_conflict(self):
        order = self.create_order()
        self.pay_order(order)
        for s in (
            OrderStatus.ACCEPTED, OrderStatus.PREPARING, OrderStatus.READY,
            OrderStatus.COURIER_ASSIGNED, OrderStatus.PICKED_UP,
        ):
            transition_order(order, s)
        response = self.api.post(f"{ORDER_URL}{order.id}/cancel/", {}, format="json")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "cannot_cancel")
        self.assertFalse(Refund.objects.exists())


@override_settings(ALLOW_STUB_PAYMENTS=True)
class ShopOrderTests(BaseFlowersTestCase):
    def test_pending_list_and_phone_hidden(self):
        order = self.create_order()
        self.pay_order(order)
        self.as_staff()
        response = self.api.get("/api/v1/shop/orders/?status=pending")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["count"], 1)
        detail = self.api.get(f"/api/v1/shop/orders/{order.id}/")
        self.assertIsNone(detail.data["recipient_phone"])

    def test_accept_shows_phone_and_moves_to_preparing(self):
        order = self.create_order()
        self.pay_order(order)
        self.as_staff()
        response = self.api.post(
            f"/api/v1/shop/orders/{order.id}/accept/", {"eta_minutes": 20}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.PREPARING)
        detail = self.api.get(f"/api/v1/shop/orders/{order.id}/")
        self.assertEqual(detail.data["recipient_phone"], "+992900000009")

    def test_ready(self):
        order = self.create_order()
        self.pay_order(order)
        self.as_staff()
        self.api.post(
            f"/api/v1/shop/orders/{order.id}/accept/", {"eta_minutes": 15}, format="json"
        )
        response = self.api.post(f"/api/v1/shop/orders/{order.id}/ready/", {}, format="json")
        self.assertEqual(response.status_code, 200)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.READY)

    def test_reject_requires_reason_and_refunds(self):
        order = self.create_order()
        self.pay_order(order)
        self.as_staff()
        bad = self.api.post(f"/api/v1/shop/orders/{order.id}/reject/", {}, format="json")
        self.assertEqual(bad.status_code, 400)
        response = self.api.post(
            f"/api/v1/shop/orders/{order.id}/reject/",
            {"reason": "Нет цветов"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.REJECTED)
        self.assertEqual(order.cancel_reason, "Нет цветов")
        refund = Refund.objects.get(payment__order=order)
        self.assertEqual(refund.amount, order.total)

    def test_foreign_shop_forbidden(self):
        order = self.create_order()
        self.pay_order(order)
        self.as_staff(self.other_staff)
        for url_suffix in ("", "accept/", "reject/", "ready/"):
            url = f"/api/v1/shop/orders/{order.id}/{url_suffix}"
            response = (
                self.api.get(url) if not url_suffix else self.api.post(url, {}, format="json")
            )
            self.assertEqual(response.status_code, 404, url)

    def test_client_cannot_access_shop_panel(self):
        response = self.api.get("/api/v1/shop/orders/")
        self.assertEqual(response.status_code, 403)

    def test_pending_list_has_expires_at(self):
        """expires_at = вход в shop_pending (updated_at) + таймаут Celery-задачи."""
        from orders.tasks import SHOP_ACCEPT_TIMEOUT_SECONDS

        order = self.create_order()
        self.pay_order(order)
        self.as_staff()
        response = self.api.get("/api/v1/shop/orders/?status=pending")
        self.assertEqual(response.status_code, 200, response.data)
        item = next(i for i in response.data["results"] if i["id"] == order.id)
        raw = item["expires_at"]
        # в тестах response.data не отрендерен в JSON — приходит datetime объектом
        expires_at = (
            raw if isinstance(raw, timezone.datetime)
            else timezone.datetime.fromisoformat(raw)
        )
        order.refresh_from_db()
        self.assertEqual(
            expires_at, order.updated_at + timedelta(seconds=SHOP_ACCEPT_TIMEOUT_SECONDS)
        )

    def test_expires_at_null_when_not_pending(self):
        order = self.create_order()  # created — не shop_pending
        self.as_staff()
        response = self.api.get("/api/v1/shop/orders/?status=history")
        item = next(i for i in response.data["results"] if i["id"] == order.id)
        self.assertIsNone(item["expires_at"])


@override_settings(ALLOW_STUB_PAYMENTS=True)
class TimeoutTaskTests(BaseFlowersTestCase):
    def test_expire_unpaid_releases_promo(self):
        order = self.create_order(promo_code="SPRING10")
        expire_unpaid_order(order.id)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.EXPIRED)
        self.assertFalse(PromoCodeUse.objects.filter(order=order).exists())
        self.promo.refresh_from_db()
        self.assertEqual(self.promo.uses_count, 0)

    def test_expire_paid_order_is_noop(self):
        order = self.create_order()
        self.pay_order(order)
        expire_unpaid_order(order.id)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.SHOP_PENDING)

    def test_shop_timeout_refunds_and_penalizes(self):
        order = self.create_order()
        self.pay_order(order)
        shop_response_timeout(order.id)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.TIMEOUT)
        refund = Refund.objects.get(payment__order=order)
        self.assertEqual(refund.amount, order.total)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.consecutive_timeouts, 1)
        self.assertFalse(self.shop.is_hidden)

    def test_shop_timeout_after_accept_is_noop(self):
        order = self.create_order()
        self.pay_order(order)
        transition_order(order, OrderStatus.ACCEPTED)
        shop_response_timeout(order.id)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.ACCEPTED)
        self.assertFalse(Refund.objects.exists())

    def test_three_timeouts_hide_shop(self):
        for _ in range(3):
            order = self.create_order()
            self.pay_order(order)
            shop_response_timeout(order.id)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.consecutive_timeouts, 3)
        self.assertTrue(self.shop.is_hidden)
        self.assertEqual(self.shop.status, Shop.Status.APPROVED)
        # скрытый магазин не попадает в выдачу
        response = self.api.get("/api/v1/shops/")
        self.assertEqual(response.status_code, 200)
        ids = [s["id"] for s in response.data["results"]]
        self.assertNotIn(self.shop.id, ids)


@override_settings(ALLOW_STUB_PAYMENTS=True)
class ReviewTests(BaseFlowersTestCase):
    def test_review_updates_shop_rating(self):
        order = self.create_order()
        self.pay_order(order)
        for s in (OrderStatus.ACCEPTED, OrderStatus.PREPARING, OrderStatus.READY):
            transition_order(order, s)
        # доводим до delivered напрямую (курьерские переходы — следующий этап)
        for s in (
            OrderStatus.COURIER_ASSIGNED, OrderStatus.PICKED_UP,
            OrderStatus.ON_THE_WAY, OrderStatus.ARRIVED, OrderStatus.DELIVERED,
        ):
            transition_order(order, s)
        response = self.api.post(
            f"{ORDER_URL}{order.id}/review/",
            {"shop_rating": 5, "text": "Отлично!"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.shop.refresh_from_db()
        self.assertEqual(self.shop.rating_avg, Decimal("5.00"))
        self.assertEqual(self.shop.rating_count, 1)
        again = self.api.post(
            f"{ORDER_URL}{order.id}/review/", {"shop_rating": 1}, format="json"
        )
        self.assertEqual(again.status_code, 409)

    def test_review_before_delivery_conflict(self):
        order = self.create_order()
        response = self.api.post(
            f"{ORDER_URL}{order.id}/review/", {"shop_rating": 5}, format="json"
        )
        self.assertEqual(response.status_code, 409)


class OrderListDetailTests(BaseFlowersTestCase):
    def test_list_active_and_history(self):
        active_order = self.create_order()
        history_order = self.create_order()
        transition_order(history_order, OrderStatus.CANCELLED_CLIENT)

        active = self.api.get(f"{ORDER_URL}?status=active")
        self.assertEqual([o["id"] for o in active.data["results"]], [active_order.id])
        history = self.api.get(f"{ORDER_URL}?status=history")
        self.assertEqual([o["id"] for o in history.data["results"]], [history_order.id])

    def test_detail_contains_pin_items_history(self):
        order = self.create_order()
        response = self.api.get(f"{ORDER_URL}{order.id}/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["delivery_pin"], order.delivery.pin_code)
        self.assertEqual(len(response.data["items"]), 1)
        self.assertEqual(
            response.data["status_history"][0]["status"], OrderStatus.CREATED
        )

    def test_foreign_order_not_found(self):
        order = self.create_order()
        other = User.objects.create_user(phone="+992900000099")
        self.api.force_authenticate(other)
        response = self.api.get(f"{ORDER_URL}{order.id}/")
        self.assertEqual(response.status_code, 404)


class CatalogTests(BaseFlowersTestCase):
    def test_shops_geo_sorted_with_distance(self):
        response = self.api.get(f"/api/v1/shops/?lat={LAT}&lng={LNG}")
        self.assertEqual(response.status_code, 200, response.data)
        results = response.data["results"]
        self.assertEqual(len(results), 2)
        # магазин в точке запроса — первый, дистанция ~0
        self.assertEqual(results[0]["id"], self.shop.id)
        self.assertEqual(results[0]["distance_m"], 0)
        self.assertTrue(results[0]["is_open"])
        self.assertIsNotNone(results[0]["delivery_time_est"])

    def test_shops_open_now_filter(self):
        ShopWorkingHours.objects.filter(shop=self.other_shop).update(is_day_off=True)
        response = self.api.get("/api/v1/shops/?open_now=1")
        ids = [s["id"] for s in response.data["results"]]
        self.assertIn(self.shop.id, ids)
        self.assertNotIn(self.other_shop.id, ids)

    def test_shop_detail(self):
        response = self.api.get(f"/api/v1/shops/{self.shop.id}/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["working_hours"]), 7)
        self.assertEqual(response.data["zones"][0]["name"], "Центр")

    def test_products_filters(self):
        response = self.api.get(f"/api/v1/products/?shop_id={self.shop.id}")
        self.assertEqual(response.data["count"], 2)
        response = self.api.get(f"/api/v1/products/?price_max=200&shop_id={self.shop.id}")
        self.assertEqual(response.data["count"], 1)
        response = self.api.get("/api/v1/products/?q=розы")
        self.assertEqual(response.data["count"], 1)

    def test_product_unavailable_hidden_by_default(self):
        self.product2.is_available = False
        self.product2.save(update_fields=["is_available"])
        response = self.api.get(f"/api/v1/products/?shop_id={self.shop.id}")
        self.assertEqual(response.data["count"], 1)
        response = self.api.get(f"/api/v1/products/?shop_id={self.shop.id}&available=0")
        self.assertEqual(response.data["count"], 2)

    def test_categories(self):
        response = self.api.get("/api/v1/categories/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)


class HistoryImmutabilityTests(BaseFlowersTestCase):
    def test_every_transition_writes_history(self):
        order = self.create_order()
        transition_order(order, OrderStatus.CANCELLED_CLIENT)
        self.assertEqual(
            OrderStatusHistory.objects.filter(order=order).count(), 2
        )


def _jpeg_file(name="bouquet.jpg"):
    """Валидный JPEG в памяти (Pillow стоит — ImageField его использует)."""
    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (8, 8), (200, 30, 90)).save(buf, "JPEG")
    buf.seek(0)
    return SimpleUploadedFile(name, buf.read(), content_type="image/jpeg")


@override_settings(ALLOW_STUB_PAYMENTS=True)
class OrderPhotoTests(BaseFlowersTestCase):
    """Фотоотчёт букета: магазин → клиент (api.md §5)."""

    def setUp(self):
        super().setUp()
        self._media = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self._media, ignore_errors=True)
        self._override = override_settings(MEDIA_ROOT=self._media)
        self._override.enable()
        self.addCleanup(self._override.disable)

    def _accepted_order(self, status=OrderStatus.PREPARING):
        order = self.create_order()
        self.pay_order(order)
        transition_order(order, OrderStatus.ACCEPTED)
        if status != OrderStatus.ACCEPTED:
            transition_order(order, status)
        return order

    def _photo_url(self, order):
        return f"/api/v1/shop/orders/{order.id}/photo/"

    def _respond_url(self, order):
        return f"{ORDER_URL}{order.id}/photo/respond/"

    def test_upload_success_and_client_sees_it(self):
        order = self._accepted_order()
        self.as_staff()
        response = self.api.post(
            self._photo_url(order), {"image": _jpeg_file()}, format="multipart"
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertIsNone(response.data["approved"])
        photo = OrderPhoto.objects.get(order=order)
        self.assertIsNone(photo.approved)
        # клиент видит bouquet_photo в деталях
        self.api.force_authenticate(self.client_user)
        detail = self.api.get(f"{ORDER_URL}{order.id}/")
        bouquet = detail.data["bouquet_photo"]
        self.assertIsNotNone(bouquet)
        self.assertIn(photo.image.url, bouquet["url"])
        self.assertIsNone(bouquet["approved"])

    def test_upload_only_shop_staff(self):
        order = self._accepted_order()
        response = self.api.post(  # клиент
            self._photo_url(order), {"image": _jpeg_file()}, format="multipart"
        )
        self.assertEqual(response.status_code, 403)

    def test_upload_foreign_shop_not_found(self):
        order = self._accepted_order()
        self.as_staff(self.other_staff)
        response = self.api.post(
            self._photo_url(order), {"image": _jpeg_file()}, format="multipart"
        )
        self.assertEqual(response.status_code, 404)

    def test_upload_wrong_status_conflict(self):
        order = self.create_order()
        self.pay_order(order)  # shop_pending — ещё не принят
        self.as_staff()
        response = self.api.post(
            self._photo_url(order), {"image": _jpeg_file()}, format="multipart"
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["error"]["code"], "invalid_state")

    def test_upload_non_image_rejected(self):
        order = self._accepted_order()
        self.as_staff()
        fake = SimpleUploadedFile("notes.txt", b"not an image", content_type="text/plain")
        response = self.api.post(
            self._photo_url(order), {"image": fake}, format="multipart"
        )
        self.assertEqual(response.status_code, 400)
        self.assertFalse(OrderPhoto.objects.exists())

    def test_respond_approved_once(self):
        order = self._accepted_order()
        self.as_staff()
        self.api.post(self._photo_url(order), {"image": _jpeg_file()}, format="multipart")
        self.api.force_authenticate(self.client_user)
        response = self.api.post(
            self._respond_url(order), {"approved": True}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        photo = OrderPhoto.objects.get(order=order)
        self.assertTrue(photo.approved)
        # клиент видит отметку в деталях
        detail = self.api.get(f"{ORDER_URL}{order.id}/")
        self.assertTrue(detail.data["bouquet_photo"]["approved"])
        # второй ответ — конфликт
        again = self.api.post(
            self._respond_url(order), {"approved": False}, format="json"
        )
        self.assertEqual(again.status_code, 409)

    def test_respond_rejected(self):
        order = self._accepted_order()
        self.as_staff()
        self.api.post(self._photo_url(order), {"image": _jpeg_file()}, format="multipart")
        self.api.force_authenticate(self.client_user)
        response = self.api.post(
            self._respond_url(order), {"approved": False}, format="json"
        )
        self.assertEqual(response.status_code, 200)
        self.assertFalse(OrderPhoto.objects.get(order=order).approved)

    def test_respond_only_owner(self):
        order = self._accepted_order()
        self.as_staff()
        self.api.post(self._photo_url(order), {"image": _jpeg_file()}, format="multipart")
        other = User.objects.create_user(phone="+992900000098")
        self.api.force_authenticate(other)
        response = self.api.post(
            self._respond_url(order), {"approved": True}, format="json"
        )
        self.assertEqual(response.status_code, 404)

    def test_respond_without_photo_conflict(self):
        order = self._accepted_order()
        response = self.api.post(
            self._respond_url(order), {"approved": True}, format="json"
        )
        self.assertEqual(response.status_code, 409)

    def test_detail_bouquet_photo_null_without_upload(self):
        order = self._accepted_order()
        response = self.api.get(f"{ORDER_URL}{order.id}/")
        self.assertIsNone(response.data["bouquet_photo"])
