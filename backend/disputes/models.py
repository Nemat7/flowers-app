from django.conf import settings
from django.db import models


class Dispute(models.Model):
    """Спор по заказу. SLA решения — 24 ч (напоминание саппорту через Celery)."""

    class Status(models.TextChoices):
        OPEN = "open", "Открыт"
        IN_REVIEW = "in_review", "На рассмотрении"
        RESOLVED_FULL_REFUND = "resolved_full_refund", "Решён: полный возврат"
        RESOLVED_PARTIAL_REFUND = "resolved_partial_refund", "Решён: частичный возврат"
        RESOLVED_REJECTED = "resolved_rejected", "Решён: отказ"

    order = models.ForeignKey(
        "orders.Order", on_delete=models.PROTECT, related_name="disputes"
    )
    opened_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="opened_disputes"
    )
    reason = models.CharField(max_length=500)
    photos = models.JSONField(default=list, blank=True)  # список image url
    status = models.CharField(
        max_length=30, choices=Status.choices, default=Status.OPEN, db_index=True
    )
    resolution_comment = models.CharField(max_length=500, blank=True)
    refund_amount = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True
    )
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="resolved_disputes",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "спор"
        verbose_name_plural = "споры"
        ordering = ("-id",)
        indexes = [models.Index(fields=["order"])]

    def __str__(self):
        return f"Спор по заказу {self.order_id} ({self.get_status_display()})"
