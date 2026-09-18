import uuid
from datetime import date, timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from core.api import error_response
from core.push import send_push, send_push_many
from orders.models import Order
from orders.permissions import IsShopStaff, get_staff_shop
from orders.services import transition_order
from orders.state_machine import OrderStatus

from .models import Payment, Payout, ShopBalanceTransaction
from .providers import ProviderUnavailableError, get_provider
from .serializers import PayoutSerializer, ShopBalanceTransactionSerializer


class PayOrderView(APIView):
    """POST /orders/{id}/pay/ — инициализация оплаты (api.md §4).

    До договоров с банками работает только provider="stub" (DEBUG/staging).
    Идемпотентность — header Idempotency-Key.
    """

    def post(self, request, order_id):
        order = Order.objects.filter(pk=order_id, client=request.user).first()
        if order is None:
            return error_response("not_found", "Заказ не найден", status.HTTP_404_NOT_FOUND)

        key_raw = request.headers.get("Idempotency-Key")
        if not key_raw:
            return error_response(
                "idempotency_key_required",
                "Требуется заголовок Idempotency-Key",
                status.HTTP_400_BAD_REQUEST,
            )
        try:
            idempotency_key = uuid.UUID(key_raw)
        except ValueError:
            return error_response(
                "idempotency_key_invalid",
                "Idempotency-Key должен быть UUID",
                status.HTTP_400_BAD_REQUEST,
            )

        # Идемпотентность: повтор с тем же ключом → существующий платёж
        existing = Payment.objects.filter(idempotency_key=idempotency_key).first()
        if existing is not None:
            if existing.order_id != order.id:
                return error_response(
                    "idempotency_conflict",
                    "Ключ идемпотентности уже использован другим платежом",
                    status.HTTP_409_CONFLICT,
                )
            return Response(self._payload(existing), status=status.HTTP_200_OK)

        if order.status != OrderStatus.CREATED:
            return error_response(
                "invalid_state",
                f"Заказ в статусе «{order.status}», оплата невозможна",
                status.HTTP_409_CONFLICT,
            )

        provider_name = request.data.get("provider")
        try:
            provider = get_provider(provider_name)
        except ProviderUnavailableError:
            return error_response(
                "provider_unavailable",
                "Провайдер не поддерживается (доступен только stub)",
                status.HTTP_400_BAD_REQUEST,
            )
        if provider.name == Payment.Provider.STUB and not (
            settings.DEBUG or settings.ALLOW_STUB_PAYMENTS
        ):
            return error_response(
                "stub_disabled",
                "Stub-провайдер отключён в этом окружении",
                status.HTTP_403_FORBIDDEN,
            )

        with transaction.atomic():
            payment = provider.initiate(order, idempotency_key)
            if payment.status == Payment.Status.SUCCESS:
                transition_order(order, OrderStatus.PAID)
                transition_order(order, OrderStatus.SHOP_PENDING)
                # запуск таймера принятия магазином (api.md §4, §5)
                from orders.tasks import SHOP_ACCEPT_TIMEOUT_SECONDS, shop_response_timeout

                shop_response_timeout.apply_async(
                    (order.id,), countdown=SHOP_ACCEPT_TIMEOUT_SECONDS
                )
        if payment.status == Payment.Status.SUCCESS:
            # WS + push: клиенту — статус, магазину — новый заказ (api.md §7)
            from core import ws_events

            ws_events.notify_order_status(order)
            expires_at = timezone.now() + timedelta(seconds=SHOP_ACCEPT_TIMEOUT_SECONDS)
            ws_events.notify_shop_new_order(order, expires_at)
            send_push(
                order.client, "order_status",
                {"order_id": order.id, "status": order.status},
            )
            send_push_many(
                [m.user for m in order.shop.staff.select_related("user")],
                "new_order",
                {"order_id": order.id, "number": order.number},
            )
            # SMS магазину о новом заказе (на случай закрытой панели)
            from orders.tasks import notify_shop_new_order_sms

            notify_shop_new_order_sms.apply_async((order.id,))
        return Response(self._payload(payment), status=status.HTTP_201_CREATED)

    @staticmethod
    def _payload(payment: Payment) -> dict:
        return {
            "payment_id": payment.id,
            "provider": payment.provider,
            "amount": str(payment.amount),
            "status": payment.status,
        }


# ================= финансы магазина (api.md §5) =================

def _parse_period(request):
    """?from&to (YYYY-MM-DD), по умолчанию — текущий месяц по сегодня.

    Возвращает (from_date, to_date, error_response|None).
    """
    today = timezone.localdate()
    raw_from = request.query_params.get("from")
    raw_to = request.query_params.get("to")
    try:
        date_from = date.fromisoformat(raw_from) if raw_from else today.replace(day=1)
        date_to = date.fromisoformat(raw_to) if raw_to else today
    except ValueError:
        return None, None, error_response(
            "invalid_period",
            "Параметры from/to должны быть датами в формате YYYY-MM-DD",
            status.HTTP_400_BAD_REQUEST,
        )
    if date_from > date_to:
        return None, None, error_response(
            "invalid_period",
            "Дата from не может быть позже to",
            status.HTTP_400_BAD_REQUEST,
        )
    return date_from, date_to, None


class ShopFinanceSummaryView(APIView):
    """GET /shop/finance/summary/ — баланс и итоги за период (api.md §5)."""

    permission_classes = (IsShopStaff,)

    def get(self, request):
        date_from, date_to, error = _parse_period(request)
        if error is not None:
            return error
        shop = get_staff_shop(request.user)
        txns = ShopBalanceTransaction.objects.filter(shop=shop)
        balance = txns.values_list("balance_after", flat=True).first() or Decimal("0")
        period_txns = txns.filter(
            created_at__date__gte=date_from, created_at__date__lte=date_to
        )
        by_type = {
            row["type"]: row["total"]
            for row in period_txns.values("type").annotate(total=Sum("amount"))
        }
        accrued = by_type.get(ShopBalanceTransaction.Type.ACCRUAL) or Decimal("0")
        # commission и payout в ledger хранятся со знаком минус — отдаём модули
        commission = -(by_type.get(ShopBalanceTransaction.Type.COMMISSION) or Decimal("0"))
        paid_out = -(by_type.get(ShopBalanceTransaction.Type.PAYOUT) or Decimal("0"))
        return Response(
            {
                "balance": str(balance),
                "pending_payout": str(balance),  # к выплате = текущий баланс
                "period": {"from": date_from.isoformat(), "to": date_to.isoformat()},
                "accrued": str(accrued),
                "commission": str(commission),
                "paid_out": str(paid_out),
            }
        )


class ShopFinanceTransactionsView(APIView):
    """GET /shop/finance/transactions/ — ledger магазина постранично, ?from&to&page=."""

    permission_classes = (IsShopStaff,)

    def get(self, request):
        date_from, date_to, error = _parse_period(request)
        if error is not None:
            return error
        qs = ShopBalanceTransaction.objects.filter(
            shop=get_staff_shop(request.user),
            created_at__date__gte=date_from,
            created_at__date__lte=date_to,
        ).select_related("order")
        paginator = PageNumberPagination()
        page = paginator.paginate_queryset(qs, request)
        serializer = ShopBalanceTransactionSerializer(page, many=True)
        return paginator.get_paginated_response(serializer.data)


class ShopFinancePayoutsView(ListAPIView):
    """GET /shop/finance/payouts/ — история выплат магазина."""

    permission_classes = (IsShopStaff,)
    serializer_class = PayoutSerializer

    def get_queryset(self):
        return Payout.objects.filter(
            recipient_type=Payout.RecipientType.SHOP,
            shop=get_staff_shop(self.request.user),
        ).order_by("-id")
