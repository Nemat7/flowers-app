from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.gis.admin import GISModelAdmin

from .models import Address, Device, OTPCode, User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = ("phone", "name", "role", "is_active", "is_staff", "created_at")
    list_filter = ("role", "is_active", "is_staff")
    search_fields = ("phone", "name")
    ordering = ("-created_at",)
    readonly_fields = ("created_at", "updated_at", "last_login")
    fieldsets = (
        (None, {"fields": ("phone", "password")}),
        ("Профиль", {"fields": ("name", "role")}),
        (
            "Права",
            {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")},
        ),
        ("Даты", {"fields": ("last_login", "created_at", "updated_at")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("phone", "role", "is_staff", "is_superuser")}),
    )


@admin.register(OTPCode)
class OTPCodeAdmin(admin.ModelAdmin):
    list_display = ("phone", "expires_at", "attempts", "is_used", "created_at")
    list_filter = ("is_used",)
    search_fields = ("phone",)
    readonly_fields = ("phone", "code_hash", "expires_at", "attempts", "is_used", "created_at")

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(Address)
class AddressAdmin(GISModelAdmin):
    list_display = ("label", "user", "address_text", "is_default")
    list_filter = ("is_default",)
    search_fields = ("address_text", "user__phone")


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ("user", "platform", "last_seen_at")
    list_filter = ("platform",)
    search_fields = ("user__phone", "fcm_token")
