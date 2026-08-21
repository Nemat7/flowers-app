"""Агрегаты админ-дашборда (api.md §8) — общие для REST API и HTML-страницы."""
from decimal import Decimal

from django.db.models import Count, Sum
from django.utils import timezone

from catalog.models import Shop
from delivery.models import CourierProfile
from disputes.models import Dispute
from orders.models import Order, OrderStatusHistory
from orders.state_machine import OrderStatus

ORDER_STATUS_LABELS = {
    OrderStatus.CREATED: "Создан",
    OrderStatus.PAID: "Оплачен",
    OrderStatus.SHOP_PENDING: "Ждёт магазин",
    OrderStatus.ACCEPTED: "Принят",
    OrderStatus.PREPARING: "Собирается",
    OrderStatus.READY: "Готов",
    OrderStatus.COURIER_ASSIGNED: "Курьер назначен",
    OrderStatus.PICKED_UP: "Забран курьером",
    OrderStatus.ON_THE_WAY: "В пути",
    OrderStatus.ARRIVED: "Курьер на месте",
    OrderStatus.DELIVERED: "Доставлен",
}


def _money(value) -> Decimal:
    return value if value is not None else Decimal("0")


def collect_dashboard_metrics() -> dict:
    """Заказы/GMV/выручка за сегодня и месяц + оперативные счётчики."""
    today = timezone.localdate()
    month_start = today.replace(day=1)

    orders = Order.objects.all()
    # GMV — по неотменённым заказам (api.md §8)
    not_cancelled = orders.exclude(status__in=OrderStatus.CANCELLATIONS)
    completed = orders.filter(status=OrderStatus.COMPLETED)

    def period_stats(qs, completed_qs):
        return {
            "orders": qs.count(),
            "gmv": _money(qs.aggregate(s=Sum("total"))["s"]),
            "revenue": _money(completed_qs.aggregate(s=Sum("commission_amount"))["s"]),
        }

    today_stats = period_stats(
        not_cancelled.filter(created_at__date=today),
        completed.filter(updated_at__date=today),
    )
    month_stats = period_stats(
        not_cancelled.filter(created_at__date__gte=month_start),
        completed.filter(updated_at__date__gte=month_start),
    )

    # активные = всё не в терминальных статусах и не в споре
    active_qs = orders.exclude(status__in=OrderStatus.TERMINAL).exclude(
        status=OrderStatus.DISPUTED
    )
    active_by_status = {
        row["status"]: row["count"]
        for row in active_qs.values("status").annotate(count=Count("id"))
    }

    return {
        "today": today_stats,
        "month": month_stats,
        "active_orders": {
            "total": active_qs.count(),
            "by_status": active_by_status,
        },
        "shops": {
            "approved": Shop.objects.filter(status=Shop.Status.APPROVED).count(),
            "total": Shop.objects.count(),
        },
        "couriers_online": CourierProfile.objects.filter(
            status__in=(CourierProfile.Status.ONLINE, CourierProfile.Status.BUSY)
        ).count(),
        "open_disputes": Dispute.objects.filter(
            status__in=(Dispute.Status.OPEN, Dispute.Status.IN_REVIEW)
        ).count(),
        "shop_timeouts_today": OrderStatusHistory.objects.filter(
            status=OrderStatus.TIMEOUT, created_at__date=today
        ).count(),
    }
