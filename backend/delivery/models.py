from django.conf import settings
from django.contrib.gis.db import models


class CourierProfile(models.Model):
    class Status(models.TextChoices):
        OFFLINE = "offline", "Не на линии"
        ONLINE = "online", "На линии"
        BUSY = "busy", "На заказе"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="courier_profile"
    )
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.OFFLINE, db_index=True
    )
    current_point = models.PointField(
        geography=True, srid=4326, null=True, blank=True,
        help_text="Последняя позиция; живые позиции дублируются в Redis",
    )
    rating_avg = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    rating_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "профиль курьера"
        verbose_name_plural = "профили курьеров"

    def __str__(self):
        return f"{self.user} ({self.get_status_display()})"


class Delivery(models.Model):
    class ConfirmationType(models.TextChoices):
        PIN = "pin", "PIN-код"
        PHOTO = "photo", "Фото"

    order = models.OneToOneField(
        "orders.Order", on_delete=models.CASCADE, related_name="delivery"
    )
    courier = models.ForeignKey(
        CourierProfile,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="deliveries",
    )
    fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    pin_code = models.CharField(max_length=6)  # показывается клиенту
    confirmation_type = models.CharField(
        max_length=10, choices=ConfirmationType.choices, default=ConfirmationType.PIN
    )
    confirmation_photo = models.ImageField(
        upload_to="delivery_confirmations/", null=True, blank=True
    )
    assigned_at = models.DateTimeField(null=True, blank=True)
    picked_up_at = models.DateTimeField(null=True, blank=True)
    arrived_at = models.DateTimeField(null=True, blank=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "доставка"
        verbose_name_plural = "доставки"

    def __str__(self):
        return f"Доставка заказа {self.order_id}"


class CourierLocation(models.Model):
    """Прореженный трек курьера (1 точка / 15–30 сек) для истории и споров."""

    delivery = models.ForeignKey(
        Delivery, on_delete=models.CASCADE, related_name="locations"
    )
    point = models.PointField(geography=True, srid=4326)
    recorded_at = models.DateTimeField()

    class Meta:
        verbose_name = "точка трека курьера"
        verbose_name_plural = "трек курьера"
        indexes = [models.Index(fields=["delivery"])]

    def __str__(self):
        return f"{self.delivery_id} @ {self.recorded_at}"
