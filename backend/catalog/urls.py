from django.urls import path

from .views import (
    CategoryListView,
    ProductDetailView,
    ProductListView,
    ShopDetailView,
    ShopHoursView,
    ShopListView,
    ShopProductDetailView,
    ShopProductListCreateView,
    ShopProductPhotoDeleteView,
    ShopProductPhotosView,
    ShopProductToggleAvailableView,
)

urlpatterns = [
    path("categories/", CategoryListView.as_view(), name="category-list"),
    path("shops/", ShopListView.as_view(), name="shop-list"),
    path("shops/<int:pk>/", ShopDetailView.as_view(), name="shop-detail"),
    path("products/", ProductListView.as_view(), name="product-list"),
    path("products/<int:pk>/", ProductDetailView.as_view(), name="product-detail"),
    # панель магазина (api.md §5)
    path(
        "shop/products/", ShopProductListCreateView.as_view(),
        name="shop-product-list-create",
    ),
    path(
        "shop/products/<int:pk>/", ShopProductDetailView.as_view(),
        name="shop-product-detail",
    ),
    path(
        "shop/products/<int:pk>/toggle-available/",
        ShopProductToggleAvailableView.as_view(),
        name="shop-product-toggle-available",
    ),
    path(
        "shop/products/<int:pk>/photos/", ShopProductPhotosView.as_view(),
        name="shop-product-photos",
    ),
    path(
        "shop/products/<int:pk>/photos/<int:photo_id>/",
        ShopProductPhotoDeleteView.as_view(),
        name="shop-product-photo-delete",
    ),
    path("shop/hours/", ShopHoursView.as_view(), name="shop-hours"),
]
