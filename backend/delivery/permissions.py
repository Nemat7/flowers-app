from rest_framework.permissions import BasePermission


class IsCourier(BasePermission):
    """Курьер (у пользователя есть CourierProfile)."""

    message = "Доступ только для курьеров"

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        return hasattr(request.user, "courier_profile")
