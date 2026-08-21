from django.urls import path

from .views import (
    CourierAvailableOrdersView,
    CourierCurrentOrderView,
    CourierEarningsView,
    CourierLocationView,
    CourierOrderAcceptView,
    CourierOrderArriveView,
    CourierOrderCompleteView,
    CourierOrderPickupView,
    CourierOrdersHistoryView,
    CourierStatusView,
)

urlpatterns = [
    path("courier/status/", CourierStatusView.as_view(), name="courier-status"),
    path(
        "courier/orders/current/", CourierCurrentOrderView.as_view(),
        name="courier-order-current",
    ),
    path(
        "courier/orders/available/", CourierAvailableOrdersView.as_view(),
        name="courier-orders-available",
    ),
    path(
        "courier/orders/history/", CourierOrdersHistoryView.as_view(),
        name="courier-orders-history",
    ),
    path(
        "courier/orders/<int:pk>/accept/", CourierOrderAcceptView.as_view(),
        name="courier-order-accept",
    ),
    path(
        "courier/orders/<int:pk>/pickup/", CourierOrderPickupView.as_view(),
        name="courier-order-pickup",
    ),
    path(
        "courier/orders/<int:pk>/arrive/", CourierOrderArriveView.as_view(),
        name="courier-order-arrive",
    ),
    path(
        "courier/orders/<int:pk>/complete/", CourierOrderCompleteView.as_view(),
        name="courier-order-complete",
    ),
    path("courier/location/", CourierLocationView.as_view(), name="courier-location"),
    path("courier/earnings/", CourierEarningsView.as_view(), name="courier-earnings"),
]
