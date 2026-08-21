from django.conf import settings
from django.db import models


class Notification(models.Model):
    """In-app лента уведомлений (push/SMS — транспорт, не хранится)."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications"
    )
    type = models.CharField(max_length=50)  # order_status, promo, dispute…
    title = models.CharField(max_length=255)
    body = models.CharField(max_length=500)
    data = models.JSONField(default=dict, blank=True)  # {order_id, status} — deep link
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "уведомление"
        verbose_name_plural = "уведомления"
        ordering = ("-id",)
        indexes = [models.Index(fields=["user", "is_read"])]

    def __str__(self):
        return f"{self.user_id}: {self.title}"
