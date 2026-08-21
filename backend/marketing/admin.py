from django.contrib import admin

from .models import Banner, PromoCode, PromoCodeUse


@admin.register(PromoCode)
class PromoCodeAdmin(admin.ModelAdmin):
    list_display = (
        "code", "type", "value", "valid_from", "valid_to",
        "uses_count", "max_uses", "is_active",
    )
    list_filter = ("type", "is_active")
    search_fields = ("code",)


@admin.register(PromoCodeUse)
class PromoCodeUseAdmin(admin.ModelAdmin):
    list_display = ("promo_code", "user", "order", "created_at")
    search_fields = ("promo_code__code", "user__phone", "order__number")


@admin.register(Banner)
class BannerAdmin(admin.ModelAdmin):
    list_display = ("title", "tag", "link_type", "link_value", "sort_order", "is_active")
    list_filter = ("link_type", "is_active")
    search_fields = ("title",)
