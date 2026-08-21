"""Доменные сервисы каталога: часы работы, is_open (TZ Asia/Dushanbe)."""
from datetime import datetime

from django.utils import timezone

from .models import Shop


def _is_open_at(hours_by_weekday: dict, moment: datetime) -> bool:
    """Открыт ли магазин в конкретный момент (aware datetime).

    hours_by_weekday: {weekday: ShopWorkingHours}. close_time <= open_time —
    смена через полночь.
    """
    hours = hours_by_weekday.get(moment.weekday())
    if hours is None or hours.is_day_off:
        return False
    t = moment.time()
    if hours.close_time <= hours.open_time:  # ночная смена
        return t >= hours.open_time or t < hours.close_time
    return hours.open_time <= t < hours.close_time


def is_shop_open(shop: Shop, at: datetime | None = None) -> bool:
    """is_open из ShopWorkingHours + текущего времени (api.md §2)."""
    moment = timezone.localtime(at) if at else timezone.localtime()
    hours_by_weekday = {h.weekday: h for h in shop.working_hours.all()}
    return _is_open_at(hours_by_weekday, moment)


def is_open_at_moment(shop: Shop, moment: datetime) -> bool:
    """Попадает ли произвольный слот (scheduled_at) в рабочие часы магазина."""
    hours_by_weekday = {h.weekday: h for h in shop.working_hours.all()}
    return _is_open_at(hours_by_weekday, timezone.localtime(moment))


def delivery_time_est(distance_m: float | None) -> int | None:
    """Оценка времени доставки в минутах: сборка + поездка (грубая оценка)."""
    if distance_m is None:
        return None
    return int(round(20 + (distance_m / 1000) * 4))
