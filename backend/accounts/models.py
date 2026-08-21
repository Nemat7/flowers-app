import hashlib
import hmac

from django.conf import settings
from django.contrib.auth.base_user import BaseUserManager
from django.contrib.auth.models import AbstractBaseUser, PermissionsMixin
from django.contrib.gis.db import models
from django.utils import timezone


class UserManager(BaseUserManager):
    def create_user(self, phone, password=None, **extra_fields):
        if not phone:
            raise ValueError("У пользователя должен быть телефон")
        user = self.model(phone=phone, **extra_fields)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, phone, password=None, **extra_fields):
        extra_fields.setdefault("role", User.Role.ADMIN)
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        if extra_fields.get("is_staff") is not True:
            raise ValueError("Суперюзер должен иметь is_staff=True")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Суперюзер должен иметь is_superuser=True")
        return self.create_user(phone, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """Логин по телефону (OTP), пароль не используется."""

    class Role(models.TextChoices):
        CLIENT = "client", "Клиент"
        SHOP_STAFF = "shop_staff", "Сотрудник магазина"
        COURIER = "courier", "Курьер"
        ADMIN = "admin", "Администратор"

    phone = models.CharField("телефон", max_length=16, unique=True)  # E.164: +992XXXXXXXXX
    name = models.CharField("имя", max_length=100, blank=True)
    role = models.CharField("роль", max_length=20, choices=Role.choices, default=Role.CLIENT)
    is_active = models.BooleanField("активен", default=True)
    is_staff = models.BooleanField("доступ в админку", default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS = []

    class Meta:
        verbose_name = "пользователь"
        verbose_name_plural = "пользователи"

    def __str__(self):
        return f"{self.phone} ({self.get_role_display()})"


class OTPCode(models.Model):
    phone = models.CharField(max_length=16, db_index=True)
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    is_used = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "OTP-код"
        verbose_name_plural = "OTP-коды"
        ordering = ("-id",)

    def __str__(self):
        return f"OTP {self.phone} (used={self.is_used})"

    @property
    def is_expired(self):
        return timezone.now() >= self.expires_at

    def set_code(self, code: str):
        self.code_hash = self._hash(code)

    def check_code(self, code: str) -> bool:
        return hmac.compare_digest(self.code_hash, self._hash(code))

    @staticmethod
    def _hash(code: str) -> str:
        # Код в открытом виде не храним — HMAC-SHA256 с SECRET_KEY сервера
        return hmac.new(
            settings.SECRET_KEY.encode(), code.encode(), hashlib.sha256
        ).hexdigest()


class Address(models.Model):
    """Сохранённый адрес клиента."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="addresses"
    )
    label = models.CharField("метка", max_length=50)
    point = models.PointField(geography=True, srid=4326)
    address_text = models.CharField("адрес", max_length=255)
    entrance = models.CharField("подъезд", max_length=10, blank=True)
    floor = models.CharField("этаж", max_length=10, blank=True)
    apartment = models.CharField("квартира", max_length=10, blank=True)
    comment = models.CharField("комментарий", max_length=255, blank=True)
    is_default = models.BooleanField(default=False)

    class Meta:
        verbose_name = "адрес"
        verbose_name_plural = "адреса"

    def __str__(self):
        return f"{self.label}: {self.address_text}"


class Device(models.Model):
    """Push-токены устройств (FCM)."""

    class Platform(models.TextChoices):
        IOS = "ios", "iOS"
        ANDROID = "android", "Android"
        WEB = "web", "Web"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="devices"
    )
    fcm_token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=10, choices=Platform.choices)
    last_seen_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "устройство"
        verbose_name_plural = "устройства"

    def __str__(self):
        return f"{self.user_id} / {self.platform}"
