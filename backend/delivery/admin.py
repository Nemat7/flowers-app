from django.contrib import admin
from django.contrib.gis.admin import GISModelAdmin

from .models import CourierLocation, CourierProfile, Delivery


@admin.register(CourierProfile)
class CourierProfileAdmin(GISModelAdmin):
    list_display = ("user", "status", "rating_avg", "rating_count", "created_at")
    list_filter = ("status",)
    search_fields = ("user__phone", "user__name")


@admin.register(Delivery)
class DeliveryAdmin(admin.ModelAdmin):
    list_display = (
        "order", "courier", "fee", "confirmation_type",
        "assigned_at", "delivered_at",
    )
    list_filter = ("confirmation_type",)
    search_fields = ("order__number", "courier__user__phone")
    readonly_fields = ("created_at",)


@admin.register(CourierLocation)
class CourierLocationAdmin(GISModelAdmin):
    list_display = ("delivery", "recorded_at")
    search_fields = ("delivery__order__number",)
