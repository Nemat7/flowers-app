from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models


class Review(models.Model):
    """Один отзыв на заказ; денормализация — в Shop.rating_avg/rating_count."""

    order = models.OneToOneField(
        "orders.Order", on_delete=models.CASCADE, related_name="review"
    )
    client = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="reviews"
    )
    shop = models.ForeignKey(
        "catalog.Shop", on_delete=models.PROTECT, related_name="reviews"
    )
    shop_rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    courier_rating = models.PositiveSmallIntegerField(
        null=True, blank=True, validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    text = models.CharField(max_length=1000, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "отзыв"
        verbose_name_plural = "отзывы"
        ordering = ("-id",)
        indexes = [models.Index(fields=["shop"])]

    def __str__(self):
        return f"Отзыв на заказ {self.order_id} ({self.shop_rating})"
