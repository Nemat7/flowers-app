from django.contrib import admin
from django.contrib.gis.admin import GISModelAdmin

from core.admin import ReadOnlyAdminMixin

from .models import Order, OrderItem, OrderPhoto, OrderStatusHistory


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    extra = 0


class OrderStatusHistoryInline(ReadOnlyAdminMixin, admin.TabularInline):
    model = OrderStatusHistory
    extra = 0
    can_delete = False


@admin.register(Order)
class OrderAdmin(GISModelAdmin):
    list_display = (
        "number", "client", "shop", "status", "total", "slot_type", "created_at",
    )
    list_filter = ("status", "slot_type", "shop")
    search_fields = ("number", "client__phone", "recipient_phone", "recipient_name")
    readonly_fields = ("created_at", "updated_at")
    inlines = (OrderItemInline, OrderStatusHistoryInline)
    date_hierarchy = "created_at"


@admin.register(OrderStatusHistory)
class OrderStatusHistoryAdmin(ReadOnlyAdminMixin, admin.ModelAdmin):
    list_display = ("order", "status", "changed_by", "created_at")
    list_filter = ("status",)
    search_fields = ("order__number",)


@admin.register(OrderPhoto)
class OrderPhotoAdmin(admin.ModelAdmin):
    list_display = ("order", "approved", "created_at")
    list_filter = ("approved",)
