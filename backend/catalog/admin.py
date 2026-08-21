from django.contrib import admin
from django.contrib.gis.admin import GISModelAdmin

from .models import Category, Product, ProductPhoto, Shop, ShopStaff, ShopWorkingHours


class ShopWorkingHoursInline(admin.TabularInline):
    model = ShopWorkingHours
    extra = 0


class ShopStaffInline(admin.TabularInline):
    model = ShopStaff
    extra = 0


class ProductPhotoInline(admin.TabularInline):
    model = ProductPhoto
    extra = 0


@admin.register(Shop)
class ShopAdmin(GISModelAdmin):
    list_display = (
        "name", "status", "is_own", "rating_avg", "commission_rate", "phone",
        "created_at",
    )
    list_filter = ("status", "is_own")
    list_editable = ("is_own",)
    search_fields = ("name", "inn", "legal_name", "phone")
    filter_horizontal = ("zones",)
    inlines = (ShopWorkingHoursInline, ShopStaffInline)


@admin.register(ShopStaff)
class ShopStaffAdmin(admin.ModelAdmin):
    list_display = ("user", "shop", "role")
    list_filter = ("role",)
    search_fields = ("user__phone", "shop__name")


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ("name", "slug", "sort_order", "is_active")
    list_filter = ("is_active",)
    search_fields = ("name", "slug")
    prepopulated_fields = {"slug": ("name",)}


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = (
        "name", "shop", "category", "price", "is_available", "is_featured",
        "is_active",
    )
    list_filter = ("is_available", "is_featured", "is_active", "category", "shop")
    list_editable = ("is_featured",)
    search_fields = ("name", "shop__name")
    inlines = (ProductPhotoInline,)


@admin.register(ProductPhoto)
class ProductPhotoAdmin(admin.ModelAdmin):
    list_display = ("product", "sort_order")
    search_fields = ("product__name",)
