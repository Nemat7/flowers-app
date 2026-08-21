import uuid

from django.conf import settings
from django.db import models


class Payment(models.Model):
    class Provider(models.TextChoices):
        ALIF = "alif", "Алиф"
        DC = "dc", "Душанбе Сити"
        STUB = "stub", "Тестовый контур (stub)"

    class Status(models.TextChoices):
        PENDING = "pending", "Ожидает"
        SUCCESS = "success", "Успешен"
        FAILED = "failed", "Ошибка"
        REFUNDED = "refunded", "Возвращён"
        PARTIALLY_REFUNDED = "partially_refunded", "Частично возвращён"

    order = models.ForeignKey(
        "orders.Order", on_delete=models.PROTECT, related_name="payments"
    )
    provider = models.CharField(max_length=10, choices=Provider.choices)
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.PENDING, db_index=True
    )
    provider_txn_id = models.CharField(
        max_length=100, null=True, blank=True, unique=True, db_index=True
    )
    # защита от двойной оплаты при ретраях клиента
    idempotency_key = models.UUIDField(unique=True, default=uuid.uuid4)
    raw_callback = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "платёж"
        verbose_name_plural = "платежи"
        constraints = [
            # один успешный платёж на заказ
            models.UniqueConstraint(
                fields=["order"],
                condition=models.Q(status="success"),
                name="unique_successful_payment_per_order",
            )
        ]
        indexes = [models.Index(fields=["order"])]

    def __str__(self):
        return f"{self.provider} {self.amount} ({self.status})"


class Refund(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Ожидает"
        SUCCESS = "success", "Успешен"
        FAILED = "failed", "Ошибка"

    payment = models.ForeignKey(Payment, on_delete=models.PROTECT, related_name="refunds")
    amount = models.DecimalField(max_digits=10, decimal_places=2)  # ≤ payment.amount − Σ refund
    reason = models.CharField(max_length=255)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING)
    provider_refund_id = models.CharField(max_length=100, null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
        help_text="null = авто-возврат",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "возврат"
        verbose_name_plural = "возвраты"

    def __str__(self):
        return f"Возврат {self.amount} по платежу #{self.payment_id}"


class ShopBalanceTransaction(models.Model):
    """Ledger магазина. Записи не редактируются."""

    class Type(models.TextChoices):
        ACCRUAL = "accrual", "Начисление (+)"
        COMMISSION = "commission", "Комиссия (−)"
        PAYOUT = "payout", "Выплата (−)"
        ADJUSTMENT = "adjustment", "Корректировка (±)"

    shop = models.ForeignKey(
        "catalog.Shop", on_delete=models.PROTECT, related_name="balance_transactions"
    )
    order = models.ForeignKey(
        "orders.Order", on_delete=models.SET_NULL, null=True, blank=True, related_name="+"
    )
    type = models.CharField(max_length=20, choices=Type.choices)
    amount = models.DecimalField(max_digits=10, decimal_places=2)  # со знаком
    balance_after = models.DecimalField(max_digits=10, decimal_places=2)
    comment = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "транзакция баланса магазина"
        verbose_name_plural = "баланс магазинов (ledger)"
        ordering = ("-id",)
        indexes = [models.Index(fields=["shop"])]

    def __str__(self):
        return f"{self.shop_id} {self.type} {self.amount}"


class Payout(models.Model):
    """Выплата магазину или курьеру. В MVP подтверждается вручную админом."""

    class RecipientType(models.TextChoices):
        SHOP = "shop", "Магазин"
        COURIER = "courier", "Курьер"

    class Method(models.TextChoices):
        ALIF = "alif", "Алиф"
        DC = "dc", "Душанбе Сити"
        BANK = "bank", "Банк"
        CASH = "cash", "Наличные"

    class Status(models.TextChoices):
        PENDING = "pending", "Ожидает"
        PAID = "paid", "Выплачена"
        FAILED = "failed", "Ошибка"

    recipient_type = models.CharField(max_length=10, choices=RecipientType.choices)
    shop = models.ForeignKey(
        "catalog.Shop", on_delete=models.PROTECT, null=True, blank=True, related_name="payouts"
    )
    courier = models.ForeignKey(
        "delivery.CourierProfile",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="payouts",
    )
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    method = models.CharField(max_length=10, choices=Method.choices)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING)
    period_from = models.DateField()
    period_to = models.DateField()
    confirmed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    paid_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "выплата"
        verbose_name_plural = "выплаты"

    def __str__(self):
        return f"{self.get_recipient_type_display()} {self.amount} ({self.status})"
