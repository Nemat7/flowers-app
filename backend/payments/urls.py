from django.urls import path

from .views import (
    PayOrderView,
    ShopFinancePayoutsView,
    ShopFinanceSummaryView,
    ShopFinanceTransactionsView,
)

urlpatterns = [
    path("orders/<int:order_id>/pay/", PayOrderView.as_view(), name="order-pay"),
    # финансы магазина (api.md §5)
    path(
        "shop/finance/summary/", ShopFinanceSummaryView.as_view(),
        name="shop-finance-summary",
    ),
    path(
        "shop/finance/transactions/", ShopFinanceTransactionsView.as_view(),
        name="shop-finance-transactions",
    ),
    path(
        "shop/finance/payouts/", ShopFinancePayoutsView.as_view(),
        name="shop-finance-payouts",
    ),
]
