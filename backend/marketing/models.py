from django.conf import settings
from django.db import models


class PromoCode(models.Model):
    class Type(models.TextChoices):
        PERCENT = "percent", "Процент"
        FIXED = "fixed", "Фиксированная сумма"
        FREE_DELIVERY = "free_delivery", "Бесплатная доставка"

    code = models.CharField(max_length=30, unique=True)  # регистронезависимый
    type = models.CharField(max_length=20, choices=Type.choices)
    value = models.DecimalField(max_digits=10, decimal_places=2)  # % или сумма
    min_order_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    valid_from = models.DateTimeField()
    valid_to = models.DateTimeField()
    max_uses = models.PositiveIntegerField(null=True, blank=True)  # null = безлимит
    uses_count = models.PositiveIntegerField(default=0)
    per_user_limit = models.PositiveIntegerField(default=1)
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name = "промокод"
        verbose_name_plural = "промокоды"

    def __str__(self):
        return self.code

    def save(self, *args, **kwargs):
        self.code = self.code.upper()
        super().save(*args, **kwargs)


class PromoCodeUse(models.Model):
    promo_code = models.ForeignKey(
        PromoCode, on_delete=models.CASCADE, related_name="uses"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="promo_uses"
    )
    order = models.ForeignKey(
        "orders.Order", on_delete=models.CASCADE, related_name="promo_uses"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "использование промокода"
        verbose_name_plural = "использования промокодов"
        constraints = [
            models.UniqueConstraint(
                fields=["promo_code", "order"], name="unique_promo_per_order"
            )
        ]
        indexes = [models.Index(fields=["promo_code", "user"])]

    def __str__(self):
        return f"{self.promo_code} / заказ {self.order_id}"


class Banner(models.Model):
    class LinkType(models.TextChoices):
        SHOP = "shop", "Магазин"
        CATEGORY = "category", "Категория"
        PROMO = "promo", "Промокод"
        URL = "url", "URL"

    title = models.CharField(max_length=150)
    # надпись-категория над заголовком: «Акция», «Доставка» (макет v5 01-home)
    tag = models.CharField("подпись над заголовком", max_length=30, blank=True)
    image = models.ImageField(upload_to="banners/")
    link_type = models.CharField(max_length=10, choices=LinkType.choices)
    link_value = models.CharField(max_length=255)  # id или url
    sort_order = models.IntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name = "баннер"
        verbose_name_plural = "баннеры"
        ordering = ("sort_order", "id")

    def __str__(self):
        return self.title
