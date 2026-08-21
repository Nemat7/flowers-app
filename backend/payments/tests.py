"""Тесты финансов панели магазина (api.md §5) и админ-дашборда (§8)."""
from datetime import timedelta
from decimal import Decimal

from django.contrib.gis.geos import Point
from django.utils import timezone

from accounts.models import User
from delivery.models import CourierProfile
from disputes.models import Dispute
from orders.models import Order, OrderStatusHistory
from orders.state_machine import OrderStatus
from orders.tests import LAT, LNG, BaseFlowersTestCase
from payments.models import Payout, ShopBalanceTransaction

SUMMARY_URL = "/api/v1/shop/finance/summary/"
TRANSACTIONS_URL = "/api/v1/shop/finance/transactions/"
PAYOUTS_URL = "/api/v1/shop/finance/payouts/"
DASHBOARD_URL = "/api/v1/admin/dashboard/"


def make_txn(shop, type_, amount, balance_after, order=None, created_at=None):
    txn = ShopBalanceTransaction.objects.create(
        shop=shop,
        order=order,
        type=type_,
        amount=amount,
        balance_after=balance_after,
        comment="тест",
    )
    if created_at is not None:
        # auto_now_add не даёт задать дату при create — правим запросом
        ShopBalanceTransaction.objects.filter(pk=txn.pk).update(created_at=created_at)
        txn.created_at = created_at
    return txn


class ShopFinanceSummaryTests(BaseFlowersTestCase):
    def setUp(self):
        super().setUp()
        self.api.force_authenticate(self.staff_user)

    def test_summary_arithmetic(self):
        """Баланс — последний balance_after; итоги периода по типам."""
        make_txn(self.shop, "accrual", Decimal("350.00"), Decimal("350.00"))
        make_txn(self.shop, "commission", Decimal("-52.50"), Decimal("297.50"))
        make_txn(self.shop, "payout", Decimal("-200.00"), Decimal("97.50"))

        res = self.api.get(SUMMARY_URL)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["balance"], "97.50")
        self.assertEqual(data["pending_payout"], "97.50")
        self.assertEqual(data["accrued"], "350.00")
        self.assertEqual(data["commission"], "52.50")
        self.assertEqual(data["paid_out"], "200.00")
        today = timezone.localdate()
        self.assertEqual(data["period"]["from"], today.replace(day=1).isoformat())
        self.assertEqual(data["period"]["to"], today.isoformat())

    def test_summary_period_filter(self):
        """Баланс — за всё время, итоги — только за выбранный период."""
        last_month = timezone.now() - timedelta(days=40)
        make_txn(self.shop, "accrual", Decimal("500.00"), Decimal("500.00"),
                 created_at=last_month)
        make_txn(self.shop, "accrual", Decimal("350.00"), Decimal("850.00"))

        # период по умолчанию (текущий месяц): только свежее начисление
        data = self.api.get(SUMMARY_URL).json()
        self.assertEqual(data["balance"], "850.00")
        self.assertEqual(data["accrued"], "350.00")

        # явный период, покрывающий оба месяца
        date_from = (timezone.localdate() - timedelta(days=60)).isoformat()
        date_to = timezone.localdate().isoformat()
        data = self.api.get(f"{SUMMARY_URL}?from={date_from}&to={date_to}").json()
        self.assertEqual(data["accrued"], "850.00")

    def test_summary_empty_ledger(self):
        data = self.api.get(SUMMARY_URL).json()
        self.assertEqual(data["balance"], "0")
        self.assertEqual(data["accrued"], "0")

    def test_summary_invalid_period(self):
        self.assertEqual(
            self.api.get(f"{SUMMARY_URL}?from=not-a-date").status_code, 400
        )
        self.assertEqual(
            self.api.get(f"{SUMMARY_URL}?from=2026-08-10&to=2026-08-01").status_code,
            400,
        )

    def test_summary_forbidden_for_client(self):
        self.api.force_authenticate(self.client_user)
        self.assertEqual(self.api.get(SUMMARY_URL).status_code, 403)

    def test_summary_anonymous(self):
        self.api.force_authenticate(user=None)
        self.assertEqual(self.api.get(SUMMARY_URL).status_code, 401)


class ShopFinanceTransactionsTests(BaseFlowersTestCase):
    def setUp(self):
        super().setUp()
        self.api.force_authenticate(self.staff_user)

    def test_transactions_pagination(self):
        balance = Decimal("0")
        for i in range(25):
            balance += Decimal("10.00")
            make_txn(self.shop, "accrual", Decimal("10.00"), balance)

        res = self.api.get(TRANSACTIONS_URL)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["count"], 25)
        self.assertEqual(len(data["results"]), 20)
        self.assertIsNotNone(data["next"])

        data = self.api.get(f"{TRANSACTIONS_URL}?page=2").json()
        self.assertEqual(len(data["results"]), 5)
        # ordering -id: последняя страница — самые старые записи
        self.assertEqual(data["results"][-1]["balance_after"], "10.00")

    def test_transactions_fields_and_order_number(self):
        order = Order.objects.create(
            number="F-000001",
            client=self.client_user,
            shop=self.shop,
            status=OrderStatus.COMPLETED,
            recipient_name="Гульчехра",
            recipient_phone="+992900000009",
            delivery_point=Point(LNG, LAT, srid=4326),
            delivery_address_text="Рудаки 25",
            subtotal=Decimal("350.00"),
            total=Decimal("360.00"),
        )
        make_txn(self.shop, "accrual", Decimal("350.00"), Decimal("350.00"),
                 order=order)
        res = self.api.get(TRANSACTIONS_URL)
        row = res.json()["results"][0]
        self.assertEqual(row["type"], "accrual")
        self.assertEqual(row["amount"], "350.00")
        self.assertEqual(row["order_number"], "F-000001")
        self.assertEqual(row["balance_after"], "350.00")
        self.assertIn("created_at", row)
        self.assertIn("comment", row)

    def test_transactions_scoped_to_own_shop(self):
        """Чужой ledger не виден: в выдаче только транзакции своего магазина."""
        make_txn(self.shop, "accrual", Decimal("100.00"), Decimal("100.00"))
        make_txn(self.other_shop, "accrual", Decimal("999.00"), Decimal("999.00"))

        data = self.api.get(TRANSACTIONS_URL).json()
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["results"][0]["amount"], "100.00")

        # сотрудник чужого магазина видит только свой ledger
        self.api.force_authenticate(self.other_staff)
        data = self.api.get(TRANSACTIONS_URL).json()
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["results"][0]["amount"], "999.00")

    def test_transactions_period_filter(self):
        old = timezone.now() - timedelta(days=40)
        make_txn(self.shop, "accrual", Decimal("100.00"), Decimal("100.00"),
                 created_at=old)
        make_txn(self.shop, "accrual", Decimal("50.00"), Decimal("150.00"))

        data = self.api.get(TRANSACTIONS_URL).json()
        self.assertEqual(data["count"], 1)  # текущий месяц по умолчанию

        date_from = (timezone.localdate() - timedelta(days=60)).isoformat()
        data = self.api.get(f"{TRANSACTIONS_URL}?from={date_from}").json()
        self.assertEqual(data["count"], 2)


class ShopFinancePayoutsTests(BaseFlowersTestCase):
    def setUp(self):
        super().setUp()
        self.api.force_authenticate(self.staff_user)

    def test_payouts_history(self):
        Payout.objects.create(
            recipient_type=Payout.RecipientType.SHOP,
            shop=self.shop,
            amount=Decimal("500.00"),
            method=Payout.Method.ALIF,
            status=Payout.Status.PAID,
            period_from=timezone.localdate() - timedelta(days=7),
            period_to=timezone.localdate(),
            paid_at=timezone.now(),
        )
        Payout.objects.create(
            recipient_type=Payout.RecipientType.SHOP,
            shop=self.other_shop,  # чужая выплата — не должна попасть в выдачу
            amount=Decimal("999.00"),
            method=Payout.Method.BANK,
            period_from=timezone.localdate() - timedelta(days=7),
            period_to=timezone.localdate(),
        )

        res = self.api.get(PAYOUTS_URL)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["count"], 1)
        row = data["results"][0]
        self.assertEqual(row["amount"], "500.00")
        self.assertEqual(row["status"], "paid")
        self.assertEqual(row["method"], "alif")
        self.assertIsNotNone(row["paid_at"])

    def test_payouts_forbidden_for_client(self):
        self.api.force_authenticate(self.client_user)
        self.assertEqual(self.api.get(PAYOUTS_URL).status_code, 403)


class AdminDashboardTests(BaseFlowersTestCase):
    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.admin_user = User.objects.create_user(
            phone="+992900000010", role=User.Role.ADMIN, is_staff=True
        )

    def _make_order(self, number, status_, total, commission="0.00"):
        return Order.objects.create(
            number=number,
            client=self.client_user,
            shop=self.shop,
            status=status_,
            recipient_name="Гульчехра",
            recipient_phone="+992900000009",
            delivery_point=Point(LNG, LAT, srid=4326),
            delivery_address_text="Рудаки 25",
            subtotal=Decimal(total),
            total=Decimal(total),
            commission_amount=Decimal(commission),
        )

    def test_forbidden_for_non_admin(self):
        self.assertEqual(self.api.get(DASHBOARD_URL).status_code, 403)  # клиент
        self.api.force_authenticate(self.staff_user)
        self.assertEqual(self.api.get(DASHBOARD_URL).status_code, 403)  # сотрудник

    def test_anonymous(self):
        self.api.force_authenticate(user=None)
        self.assertEqual(self.api.get(DASHBOARD_URL).status_code, 401)

    def test_aggregates(self):
        self._make_order("F-000101", OrderStatus.COMPLETED, "400.00", "60.00")
        self._make_order("F-000102", OrderStatus.COMPLETED, "300.00", "45.00")
        self._make_order("F-000103", OrderStatus.CANCELLED_CLIENT, "1000.00")
        preparing = self._make_order("F-000104", OrderStatus.PREPARING, "200.00")
        timed_out = self._make_order("F-000105", OrderStatus.TIMEOUT, "150.00")
        OrderStatusHistory.objects.create(order=timed_out, status=OrderStatus.TIMEOUT)
        Dispute.objects.create(
            order=preparing, opened_by=self.client_user, reason="Не те цветы"
        )
        courier_user = User.objects.create_user(
            phone="+992900000011", role=User.Role.COURIER
        )
        CourierProfile.objects.create(
            user=courier_user, status=CourierProfile.Status.ONLINE
        )

        self.api.force_authenticate(self.admin_user)
        res = self.api.get(DASHBOARD_URL)
        self.assertEqual(res.status_code, 200)
        data = res.json()

        # GMV — без отменённых; timeout в GMV входит (не отмена клиентом)
        self.assertEqual(data["today"]["orders"], 4)
        self.assertEqual(data["today"]["gmv"], "1050.00")
        # выручка платформы — commission_amount по completed
        self.assertEqual(data["today"]["revenue"], "105.00")
        self.assertEqual(data["month"]["orders"], 4)
        self.assertEqual(data["month"]["gmv"], "1050.00")

        self.assertEqual(data["active_orders"]["total"], 1)
        self.assertEqual(data["active_orders"]["by_status"], {"preparing": 1})
        # BaseFlowersTestCase: два approved-магазина
        self.assertEqual(data["shops"], {"approved": 2, "total": 2})
        self.assertEqual(data["couriers_online"], 1)
        self.assertEqual(data["open_disputes"], 1)
        self.assertEqual(data["shop_timeouts_today"], 1)
