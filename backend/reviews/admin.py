from django.contrib import admin

from .models import Review


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    list_display = ("order", "shop", "client", "shop_rating", "courier_rating", "created_at")
    list_filter = ("shop_rating", "shop")
    search_fields = ("order__number", "client__phone", "shop__name")
