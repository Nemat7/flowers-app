from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView

from .dashboard import collect_dashboard_metrics


class AdminDashboardView(APIView):
    """GET /admin/dashboard/ — метрики дня/месяца для админки (api.md §8)."""

    permission_classes = (IsAdminUser,)

    def get(self, request):
        m = collect_dashboard_metrics()
        return Response(
            {
                "today": {
                    "orders": m["today"]["orders"],
                    "gmv": str(m["today"]["gmv"]),
                    "revenue": str(m["today"]["revenue"]),
                },
                "month": {
                    "orders": m["month"]["orders"],
                    "gmv": str(m["month"]["gmv"]),
                    "revenue": str(m["month"]["revenue"]),
                },
                "active_orders": m["active_orders"],
                "shops": m["shops"],
                "couriers_online": m["couriers_online"],
                "open_disputes": m["open_disputes"],
                "shop_timeouts_today": m["shop_timeouts_today"],
            }
        )
