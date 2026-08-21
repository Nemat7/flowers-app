from django.conf import settings
from django.contrib.gis.db import models


class Shop(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "На модерации"
        APPROVED = "approved", "Одобрен"
        REJECTED = "rejected", "Отклонён"
        SUSPENDED = "suspended", "Приостановлен"

    name = models.CharField("название", max_length=150)
    description = models.TextField("описание", blank=True)
    inn = models.CharField("ИНН", max_length=20, blank=True)
    legal_name = models.CharField("юр. название", max_length=200, blank=True)
    phone = models.CharField("телефон", max_length=16, blank=True)
    point = models.PointField(geography=True, srid=4326)
    address_text = models.CharField("адрес", max_length=255)
    logo = models.ImageField(upload_to="shops/logos/", blank=True)
    cover_photo = models.ImageField(upload_to="shops/covers/", blank=True)
    # витрина платформы: бейдж «Наш магазин» на карточке (макет v5 01-home)
    is_own = models.BooleanField("наш магазин (бренд платформы)", default=False)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.PENDING, db_index=True
    )
    # авто-скрытие из выдачи после 3 таймаутов принятия подряд (api.md §5)
    is_hidden = models.BooleanField("скрыт из выдачи (авто-штраф)", default=False)
    consecutive_timeouts = models.PositiveSmallIntegerField(
        "таймаутов принятия подряд", default=0
    )
    commission_rate = models.DecimalField(
        "комиссия платформы, %", max_digits=4, decimal_places=2, default=0
    )
    rating_avg = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    rating_count = models.PositiveIntegerField(default=0)
    min_order_amount = models.DecimalField(
        "мин. сумма заказа", max_digits=10, decimal_places=2, default=0
    )
    card_price = models.DecimalField(
        "цена открытки (0 = бесплатно)", max_digits=10, decimal_places=2, default=0
    )
    zones = models.ManyToManyField(
        "core.DeliveryZone", related_name="shops", blank=True, verbose_name="зоны доставки"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "магазин"
        verbose_name_plural = "магазины"

    def __str__(self):
        return self.name


class ShopWorkingHours(models.Model):
    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name="working_hours")
    weekday = models.PositiveSmallIntegerField("день недели")  # 0=пн … 6=вс
    open_time = models.TimeField("открытие")
    close_time = models.TimeField("закрытие")
    is_day_off = models.BooleanField("выходной", default=False)

    class Meta:
        verbose_name = "часы работы"
        verbose_name_plural = "часы работы"
        constraints = [
            models.UniqueConstraint(fields=["shop", "weekday"], name="unique_shop_weekday")
        ]

    def __str__(self):
        return f"{self.shop} — день {self.weekday}"


class ShopStaff(models.Model):
    class Role(models.TextChoices):
        OWNER = "owner", "Владелец"
        MANAGER = "manager", "Менеджер"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="shop_memberships"
    )
    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name="staff")
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.MANAGER)

    class Meta:
        verbose_name = "сотрудник магазина"
        verbose_name_plural = "сотрудники магазинов"
        constraints = [
            models.UniqueConstraint(fields=["user", "shop"], name="unique_user_shop_staff")
        ]
        indexes = [models.Index(fields=["shop"])]

    def __str__(self):
        return f"{self.user} @ {self.shop} ({self.get_role_display()})"


class Category(models.Model):
    name = models.CharField("название", max_length=100)
    slug = models.SlugField(max_length=100, unique=True)
    icon = models.CharField(max_length=100, blank=True)
    # круглая картинка категории на главной (макет v5 01-home, блок «Категории»)
    image = models.ImageField("картинка", upload_to="categories/", blank=True)
    sort_order = models.IntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name = "категория"
        verbose_name_plural = "категории"
        ordering = ("sort_order", "id")

    def __str__(self):
        return self.name


class Product(models.Model):
    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name="products")
    category = models.ForeignKey(
        Category, on_delete=models.PROTECT, related_name="products"
    )
    name = models.CharField("название", max_length=150)
    description = models.TextField("описание", blank=True)
    composition = models.CharField("состав", max_length=500, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    is_available = models.BooleanField("в наличии", default=True)
    is_active = models.BooleanField(default=True)
    # лента «Наше фирменное» на главной + бейдж «Наш бренд» (макет v5 01-home)
    is_featured = models.BooleanField("наше фирменное", default=False)
    tags = models.JSONField(default=list, blank=True)  # ["romantic", "red"]
    sort_order = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "товар"
        verbose_name_plural = "товары"
        indexes = [
            models.Index(fields=["shop", "is_available", "is_active"]),
        ]

    def __str__(self):
        return f"{self.name} ({self.shop})"


class ProductPhoto(models.Model):
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="photos")
    image = models.ImageField(upload_to="products/")
    sort_order = models.IntegerField(default=0)

    class Meta:
        verbose_name = "фото товара"
        verbose_name_plural = "фото товаров"
        ordering = ("sort_order", "id")

    def __str__(self):
        return f"Фото #{self.id} ({self.product})"
