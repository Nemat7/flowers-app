from django.conf import settings
from django.contrib.gis.db import models


class DeliveryZone(models.Model):
    """Полигон зоны доставки платформы (зоны глобальные, доставка своя)."""

    name = models.CharField("название", max_length=100)
    polygon = models.PolygonField(geography=True, srid=4326)
    base_price = models.DecimalField("базовая стоимость", max_digits=10, decimal_places=2)
    price_per_km = models.DecimalField("надбавка за км", max_digits=10, decimal_places=2)
    min_order_amount = models.DecimalField(
        "мин. сумма заказа", max_digits=10, decimal_places=2, default=0
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name = "зона доставки"
        verbose_name_plural = "зоны доставки"

    def __str__(self):
        return self.name


class AuditLog(models.Model):
    """Все действия админов и смены статусов. Записи не редактируются."""

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
        help_text="null = системное действие (Celery)",
    )
    action = models.CharField(max_length=100)  # order.status_changed, shop.blocked…
    entity_type = models.CharField(max_length=50)
    entity_id = models.BigIntegerField()
    before = models.JSONField(default=dict, blank=True)
    after = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        verbose_name = "запись аудита"
        verbose_name_plural = "аудит"
        ordering = ("-created_at",)

    def __str__(self):
        return f"{self.action} {self.entity_type}#{self.entity_id}"
