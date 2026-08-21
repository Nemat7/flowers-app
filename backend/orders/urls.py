from django.urls import path

from .views import (
    OrderCancelView,
    OrderDetailView,
    OrderListCreateView,
    OrderPhotoRespondView,
    OrderReviewView,
    ShopOrderAcceptView,
    ShopOrderDetailView,
    ShopOrderListView,
    ShopOrderPhotoUploadView,
    ShopOrderReadyView,
    ShopOrderRejectView,
)

urlpatterns = [
    path("orders/", OrderListCreateView.as_view(), name="order-list-create"),
    path("orders/<int:pk>/", OrderDetailView.as_view(), name="order-detail"),
    path("orders/<int:pk>/cancel/", OrderCancelView.as_view(), name="order-cancel"),
    path("orders/<int:pk>/review/", OrderReviewView.as_view(), name="order-review"),
    path(
        "orders/<int:pk>/photo/respond/", OrderPhotoRespondView.as_view(),
        name="order-photo-respond",
    ),
    path("shop/orders/", ShopOrderListView.as_view(), name="shop-order-list"),
    path("shop/orders/<int:pk>/", ShopOrderDetailView.as_view(), name="shop-order-detail"),
    path(
        "shop/orders/<int:pk>/accept/", ShopOrderAcceptView.as_view(),
        name="shop-order-accept",
    ),
    path(
        "shop/orders/<int:pk>/reject/", ShopOrderRejectView.as_view(),
        name="shop-order-reject",
    ),
    path(
        "shop/orders/<int:pk>/ready/", ShopOrderReadyView.as_view(),
        name="shop-order-ready",
    ),
    path(
        "shop/orders/<int:pk>/photo/", ShopOrderPhotoUploadView.as_view(),
        name="shop-order-photo",
    ),
]
