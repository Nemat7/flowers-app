from rest_framework import serializers

from .models import Category, Product, ProductPhoto, Shop, ShopWorkingHours
from .services import delivery_time_est, is_shop_open


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ("id", "name", "slug", "icon", "image", "sort_order")


class WorkingHoursSerializer(serializers.ModelSerializer):
    class Meta:
        model = ShopWorkingHours
        fields = ("weekday", "open_time", "close_time", "is_day_off")


class ShopListSerializer(serializers.ModelSerializer):
    """api.md §2: name, logo, rating, delivery_time_est, min_order, is_open, distance_m."""

    rating = serializers.DecimalField(
        source="rating_avg", max_digits=3, decimal_places=2
    )
    min_order = serializers.DecimalField(
        source="min_order_amount", max_digits=10, decimal_places=2
    )
    is_open = serializers.SerializerMethodField()
    distance_m = serializers.SerializerMethodField()
    delivery_time_est = serializers.SerializerMethodField()
    # для карточки главной (макет v5 01-home): обложка, профиль магазина,
    # мета-строка «35–45 мин · Доставка 15 с.» и подпись справа.
    kind = serializers.SerializerMethodField()
    delivery_fee_from = serializers.SerializerMethodField()

    class Meta:
        model = Shop
        fields = (
            "id", "name", "logo", "cover_photo", "is_own", "rating",
            "rating_count", "delivery_time_est", "min_order", "is_open",
            "distance_m", "kind", "delivery_fee_from",
        )

    def get_is_open(self, obj) -> bool:
        return is_shop_open(obj)

    def get_kind(self, obj) -> str | None:
        """Профиль магазина = категория его товаров («Цветы», «Сладости»).
        В списке приходит аннотацией kind_name, в детали — добираем запросом."""
        annotated = getattr(obj, "kind_name", None)
        if annotated is not None:
            return annotated
        return (
            obj.products.filter(is_active=True, is_available=True)
            .order_by("category__sort_order", "sort_order")
            .values_list("category__name", flat=True)
            .first()
        )

    def get_delivery_fee_from(self, obj):
        """Минимальная база доставки среди зон магазина («Доставка от 10 с.»).
        Точная сумма считается при оформлении — она зависит от расстояния."""
        prices = [z.base_price for z in obj.zones.all() if z.is_active]
        return min(prices) if prices else None

    def _distance_m(self, obj):
        distance = getattr(obj, "distance", None)
        return round(distance.m, 1) if distance is not None else None

    def get_distance_m(self, obj):
        return self._distance_m(obj)

    def get_delivery_time_est(self, obj):
        return delivery_time_est(self._distance_m(obj))


class ShopDetailSerializer(ShopListSerializer):
    working_hours = WorkingHoursSerializer(many=True, read_only=True)
    zones = serializers.SerializerMethodField()

    class Meta(ShopListSerializer.Meta):
        fields = ShopListSerializer.Meta.fields + (
            "description", "address_text", "phone", "card_price",
            "working_hours", "zones",
        )

    def get_zones(self, obj):
        return [
            {"id": z.id, "name": z.name, "base_price": z.base_price,
             "price_per_km": z.price_per_km}
            for z in obj.zones.filter(is_active=True)
        ]


class ProductPhotoSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductPhoto
        fields = ("id", "image", "sort_order")


class ProductListSerializer(serializers.ModelSerializer):
    photo = serializers.SerializerMethodField()

    class Meta:
        model = Product
        fields = (
            "id", "shop", "category", "name", "price", "composition",
            "tags", "is_available", "is_featured", "photo",
        )

    def get_photo(self, obj):
        first = obj.photos.first()
        if first is None:
            return None
        request = self.context.get("request")
        url = first.image.url
        return request.build_absolute_uri(url) if request else url


class ProductDetailSerializer(ProductListSerializer):
    photos = ProductPhotoSerializer(many=True, read_only=True)
    shop_detail = serializers.SerializerMethodField()

    class Meta(ProductListSerializer.Meta):
        fields = ProductListSerializer.Meta.fields + (
            "description", "photos", "shop_detail",
        )

    def get_shop_detail(self, obj):
        return {"id": obj.shop_id, "name": obj.shop.name, "rating": obj.shop.rating_avg}


# --- панель магазина (api.md §5) ---

class ShopProductSerializer(serializers.ModelSerializer):
    """Товар в панели магазина: правка всех полей + фото; is_active — только чтение
    (архив через DELETE)."""

    photos = ProductPhotoSerializer(many=True, read_only=True)
    category = serializers.PrimaryKeyRelatedField(
        queryset=Category.objects.filter(is_active=True)
    )
    category_name = serializers.CharField(source="category.name", read_only=True)

    class Meta:
        model = Product
        fields = (
            "id", "name", "category", "category_name", "price", "composition",
            "description", "is_available", "is_active", "tags", "sort_order",
            "photos", "created_at", "updated_at",
        )
        read_only_fields = ("is_active", "created_at", "updated_at")

    def validate_tags(self, tags):
        if not isinstance(tags, list) or not all(isinstance(t, str) for t in tags):
            raise serializers.ValidationError("tags — список строк")
        return tags


class ProductPhotoUploadSerializer(serializers.Serializer):
    """Одно фото из multipart-запроса; ImageField проверяет, что это изображение."""

    image = serializers.ImageField()


class WorkingHoursInputSerializer(serializers.Serializer):
    """Один день недели для PUT /shop/hours/ (массив всех 7 дней целиком)."""

    weekday = serializers.IntegerField(min_value=0, max_value=6)
    open_time = serializers.TimeField()
    close_time = serializers.TimeField()
    is_day_off = serializers.BooleanField(default=False)
