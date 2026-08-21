from rest_framework.permissions import BasePermission


class IsShopStaff(BasePermission):
    """Сотрудник магазина (запись ShopStaff). Магазин — из членства пользователя."""

    message = "Доступ только для сотрудников магазина"

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return request.user.shop_memberships.exists()


def get_staff_shop(user):
    """Магазин текущего сотрудника (первое членство). None, если не сотрудник."""
    membership = user.shop_memberships.select_related("shop").first()
    return membership.shop if membership else None
