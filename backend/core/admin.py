from django.contrib import admin
from django.contrib.gis.admin import GISModelAdmin
from django.template.response import TemplateResponse
from django.urls import path

from .dashboard import ORDER_STATUS_LABELS, collect_dashboard_metrics
from .models import AuditLog, DeliveryZone


class ReadOnlyAdminMixin:
    """Записи не редактируются вручную (аудит, история, ledger)."""

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(DeliveryZone)
class DeliveryZoneAdmin(GISModelAdmin):
    list_display = ("name", "base_price", "price_per_km", "min_order_amount", "is_active")
    list_filter = ("is_active",)
    search_fields = ("name",)


@admin.register(AuditLog)
class AuditLogAdmin(ReadOnlyAdminMixin, admin.ModelAdmin):
    list_display = ("action", "entity_type", "entity_id", "actor", "created_at")
    list_filter = ("action", "entity_type")
    search_fields = ("action", "entity_type")
    date_hierarchy = "created_at"


def dashboard_view(request):
    """HTML-дашборд в админке (api.md §8): метрики дня/месяца без JS."""
    m = collect_dashboard_metrics()
    active_rows = [
        {
            "label": ORDER_STATUS_LABELS.get(status, status),
            "count": count,
        }
        for status, count in sorted(
            m["active_orders"]["by_status"].items(), key=lambda kv: -kv[1]
        )
    ]
    context = {
        **admin.site.each_context(request),
        "title": "Дашборд",
        "m": m,
        "active_rows": active_rows,
    }
    return TemplateResponse(request, "admin/dashboard.html", context)


# URL /admin/dashboard/ рядом со стандартными URL админки
_original_get_urls = admin.site.get_urls


def _get_urls_with_dashboard():
    custom = [
        path(
            "dashboard/",
            admin.site.admin_view(dashboard_view),
            name="dashboard",
        )
    ]
    return custom + _original_get_urls()


admin.site.get_urls = _get_urls_with_dashboard
