from django.contrib import admin

from core.admin import ReadOnlyAdminMixin

from .models import Payment, Payout, Refund, ShopBalanceTransaction


class RefundInline(admin.TabularInline):
    model = Refund
    extra = 0


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ("id", "order", "provider", "amount", "status", "created_at")
    list_filter = ("provider", "status")
    search_fields = ("order__number", "provider_txn_id", "idempotency_key")
    readonly_fields = ("idempotency_key", "created_at", "updated_at")
    inlines = (RefundInline,)


@admin.register(Refund)
class RefundAdmin(admin.ModelAdmin):
    list_display = ("id", "payment", "amount", "status", "created_by", "created_at")
    list_filter = ("status",)
    search_fields = ("payment__order__number", "provider_refund_id")


@admin.register(ShopBalanceTransaction)
class ShopBalanceTransactionAdmin(ReadOnlyAdminMixin, admin.ModelAdmin):
    list_display = ("shop", "type", "amount", "balance_after", "order", "created_at")
    list_filter = ("type", "shop")
    search_fields = ("shop__name", "order__number")
    date_hierarchy = "created_at"


@admin.register(Payout)
class PayoutAdmin(admin.ModelAdmin):
    list_display = (
        "id", "recipient_type", "shop", "courier", "amount", "method",
        "status", "period_from", "period_to",
    )
    list_filter = ("recipient_type", "status", "method")
    search_fields = ("shop__name", "courier__user__phone")
