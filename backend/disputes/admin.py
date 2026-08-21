from django.contrib import admin

from .models import Dispute


@admin.register(Dispute)
class DisputeAdmin(admin.ModelAdmin):
    list_display = ("id", "order", "opened_by", "status", "refund_amount", "created_at")
    list_filter = ("status",)
    search_fields = ("order__number", "opened_by__phone", "reason")
    readonly_fields = ("created_at",)
