from rest_framework import serializers

from .models import Payout, ShopBalanceTransaction


class ShopBalanceTransactionSerializer(serializers.ModelSerializer):
    """Строка ledger магазина для панели (api.md §5)."""

    order_number = serializers.CharField(source="order.number", default=None)

    class Meta:
        model = ShopBalanceTransaction
        fields = (
            "id", "created_at", "type", "amount", "order_number",
            "comment", "balance_after",
        )


class PayoutSerializer(serializers.ModelSerializer):
    """Выплата магазину в истории панели (api.md §5)."""

    class Meta:
        model = Payout
        fields = (
            "id", "amount", "method", "status",
            "period_from", "period_to", "created_at", "paid_at",
        )
