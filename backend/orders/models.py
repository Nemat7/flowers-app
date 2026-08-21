from django.conf import settings
from django.contrib.gis.db import models


class Order(models.Model):
    class Status(models.TextChoices):
        CREATED = "created", "Создан"
        PAYMENT_FAILED = "payment_failed", "Ошибка оплаты"
        EXPIRED = "expired", "Истёк (не оплачен)"
        PAID = "paid", "Оплачен"
        SHOP_PENDING = "shop_pending", "Ждёт магазин"
        ACCEPTED = "accepted", "Принят магазином"
        REJECTED = "rejected", "Отклонён магазином"
        TIMEOUT = "timeout", "Таймаут магазина"
        PREPARING = "preparing", "Собирается"
        READY = "ready", "Готов"
        COURIER_ASSIGNED = "courier_assigned", "Курьер назначен"
        PICKED_UP = "picked_up", "Забран курьером"
        ON_THE_WAY = "on_the_way", "В пути"
        ARRIVED = "arrived", "Курьер на месте"
        DELIVERED = "delivered", "Доставлен"
        COMPLETED = "completed", "Завершён"
        CANCELLED_CLIENT = "cancelled_client", "Отменён клиентом"
        CANCELLED_SHOP = "cancelled_shop", "Отменён магазином"
        CANCELLED_ADMIN = "cancelled_admin", "Отменён платформой"
        DISPUTED = "disputed", "Спор"

    class SlotType(models.TextChoices):
        ASAP = "asap", "Как можно скорее"
        SCHEDULED = "scheduled", "Ко времени"

    number = models.CharField("публичный номер", max_length=12, unique=True)  # «F-004521»
    client = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="orders"
    )
    shop = models.ForeignKey(
        "catalog.Shop", on_delete=models.PROTECT, related_name="orders"
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.CREATED, db_index=True
    )
    # состав и открытка
    card_text = models.TextField("текст открытки", blank=True)
    card_price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    is_anonymous = models.BooleanField(default=False)
    # получатель
    recipient_name = models.CharField(max_length=100)
    recipient_phone = models.CharField(max_length=16)
    # адрес (снимок на момент заказа)
    delivery_point = models.PointField(geography=True, srid=4326)
    delivery_address_text = models.CharField(max_length=255)
    delivery_details = models.CharField(max_length=255, blank=True)
    # слот
    slot_type = models.CharField(
        max_length=10, choices=SlotType.choices, default=SlotType.ASAP
    )
    scheduled_at = models.DateTimeField(null=True, blank=True)
    # деньги (снимки, пересчёт только на сервере)
    subtotal = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    delivery_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    discount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    commission_rate = models.DecimalField(max_digits=4, decimal_places=2, default=0)
    commission_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    promo_code = models.ForeignKey(
        "marketing.PromoCode",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="orders",
    )
    comment = models.CharField("комментарий клиента", max_length=500, blank=True)
    cancel_reason = models.CharField(max_length=255, blank=True)
    # защита от двойного создания при ретраях клиента (header Idempotency-Key)
    idempotency_key = models.UUIDField(unique=True, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "заказ"
        verbose_name_plural = "заказы"
        ordering = ("-id",)
        indexes = [
            models.Index(fields=["client"]),
            models.Index(fields=["shop", "status"]),
            models.Index(fields=["status"]),
        ]

    def __str__(self):
        return f"{self.number} ({self.get_status_display()})"


class OrderItem(models.Model):
    """Позиция заказа — снимок товара на момент заказа."""

    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="items")
    product = models.ForeignKey(
        "catalog.Product", on_delete=models.SET_NULL, null=True, blank=True, related_name="+"
    )
    product_name = models.CharField(max_length=150)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    qty = models.PositiveIntegerField()
    photo_url = models.CharField(max_length=500, blank=True)

    class Meta:
        verbose_name = "позиция заказа"
        verbose_name_plural = "позиции заказа"
        indexes = [models.Index(fields=["order"])]

    def __str__(self):
        return f"{self.product_name} ×{self.qty}"


class OrderStatusHistory(models.Model):
    """Каждый переход статуса. Записи не редактируются."""

    order = models.ForeignKey(
        Order, on_delete=models.CASCADE, related_name="status_history"
    )
    status = models.CharField(max_length=20, choices=Order.Status.choices)
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
        help_text="null = система",
    )
    comment = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        verbose_name = "история статуса"
        verbose_name_plural = "история статусов"
        ordering = ("-created_at",)
        indexes = [models.Index(fields=["order"])]

    def __str__(self):
        return f"{self.order_id} → {self.status}"


class OrderPhoto(models.Model):
    """Фото собранного букета на одобрение клиенту (v1.1; таблица в MVP)."""

    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="photos")
    image = models.ImageField(upload_to="order_photos/")
    approved = models.BooleanField(null=True, blank=True)  # null = ждёт реакции клиента
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "фото заказа"
        verbose_name_plural = "фото заказов"

    def __str__(self):
        return f"Фото заказа {self.order_id}"
