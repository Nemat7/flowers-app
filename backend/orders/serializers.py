"""Сериализаторы заказов: клиент и панель магазина (api.md §3, §5)."""
from datetime import timedelta

from rest_framework import serializers

from .models import Order, OrderItem, OrderStatusHistory
from .state_machine import OrderStatus


class OrderItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderItem
        fields = ("id", "product", "product_name", "price", "qty", "photo_url")


class OrderStatusHistorySerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderStatusHistory
        fields = ("status", "comment", "created_at")


class OrderListSerializer(serializers.ModelSerializer):
    shop_name = serializers.CharField(source="shop.name", read_only=True)
    shop_logo = serializers.ImageField(source="shop.logo", read_only=True)

    class Meta:
        model = Order
        fields = (
            "id", "number", "status", "shop", "shop_name", "shop_logo",
            "slot_type", "total", "created_at",
        )


class OrderDetailSerializer(serializers.ModelSerializer):
    """Детали заказа клиента: позиции, история статусов, PIN доставки, суммы (api.md §3)."""

    items = OrderItemSerializer(many=True, read_only=True)
    status_history = OrderStatusHistorySerializer(many=True, read_only=True)
    shop_name = serializers.CharField(source="shop.name", read_only=True)
    shop_location = serializers.SerializerMethodField()
    courier = serializers.SerializerMethodField()
    delivery_pin = serializers.SerializerMethodField()
    address = serializers.SerializerMethodField()
    bouquet_photo = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = (
            "id", "number", "status", "shop", "shop_name", "shop_location",
            "courier",
            "items", "card_text", "card_price", "is_anonymous",
            "recipient_name", "recipient_phone", "address",
            "slot_type", "scheduled_at",
            "subtotal", "delivery_fee", "discount", "total",
            "cancel_reason", "comment",
            "delivery_pin", "bouquet_photo", "status_history", "created_at",
        )

    def get_shop_location(self, obj):
        point = obj.shop.point
        return {"lat": point.y, "lng": point.x} if point else None

    def get_courier(self, obj):
        # Данные курьера — только когда он назначен (для карточки «Позвонить»).
        delivery = getattr(obj, "delivery", None)
        courier = getattr(delivery, "courier", None) if delivery else None
        if not courier:
            return None
        return {"name": courier.user.name, "phone": courier.user.phone}

    def get_delivery_pin(self, obj):
        delivery = getattr(obj, "delivery", None)
        return delivery.pin_code if delivery else None

    def get_address(self, obj):
        return {
            "lat": obj.delivery_point.y,
            "lng": obj.delivery_point.x,
            "address_text": obj.delivery_address_text,
            "details": obj.delivery_details,
        }

    def get_bouquet_photo(self, obj):
        """Последнее фото букета от магазина: {url, approved} или null."""
        photo = obj.photos.order_by("-id").first()
        if photo is None:
            return None
        url = photo.image.url
        request = self.context.get("request")
        if request is not None:
            url = request.build_absolute_uri(url)
        return {"url": url, "approved": photo.approved}


# --- входные данные создания заказа ---

class OrderItemInputSerializer(serializers.Serializer):
    product_id = serializers.IntegerField()
    qty = serializers.IntegerField(min_value=1)


class OrderAddressInputSerializer(serializers.Serializer):
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    address_text = serializers.CharField(max_length=255)
    details = serializers.CharField(max_length=255, required=False, allow_blank=True)


class OrderCreateSerializer(serializers.Serializer):
    """Валидация формы запроса; доменные проверки — в orders.services.create_order."""

    shop_id = serializers.IntegerField()
    items = OrderItemInputSerializer(many=True)
    card_text = serializers.CharField(required=False, allow_blank=True, default="")
    is_anonymous = serializers.BooleanField(required=False, default=False)
    recipient_name = serializers.CharField(max_length=100)
    recipient_phone = serializers.CharField(max_length=16)
    address = OrderAddressInputSerializer()
    slot_type = serializers.ChoiceField(choices=Order.SlotType.choices)
    scheduled_at = serializers.DateTimeField(required=False, allow_null=True)
    promo_code = serializers.CharField(required=False, allow_blank=True, max_length=30)
    comment = serializers.CharField(required=False, allow_blank=True, max_length=500)

    def validate_items(self, items):
        if not items:
            raise serializers.ValidationError("Список товаров пуст")
        return items


class OrderCancelSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, max_length=255)


class OrderPhotoRespondSerializer(serializers.Serializer):
    approved = serializers.BooleanField()


class ShopOrderPhotoUploadSerializer(serializers.Serializer):
    """Фото букета от магазина; ImageField проверяет, что файл — картинка."""

    image = serializers.ImageField()


class ReviewCreateSerializer(serializers.Serializer):
    shop_rating = serializers.IntegerField(min_value=1, max_value=5)
    courier_rating = serializers.IntegerField(
        min_value=1, max_value=5, required=False, allow_null=True
    )
    text = serializers.CharField(required=False, allow_blank=True, max_length=1000)


# --- панель магазина ---

class ShopOrderListSerializer(OrderListSerializer):
    """expires_at — дедлайн принятия заказа (тот же таймаут, что у Celery-задачи
    shop_response_timeout); null для не-pending заказов."""

    expires_at = serializers.SerializerMethodField()

    class Meta(OrderListSerializer.Meta):
        fields = OrderListSerializer.Meta.fields + (
            "recipient_name", "scheduled_at", "expires_at",
        )

    def get_expires_at(self, obj):
        if obj.status != OrderStatus.SHOP_PENDING:
            return None
        from .tasks import SHOP_ACCEPT_TIMEOUT_SECONDS

        # вход в shop_pending фиксируется в updated_at (transition_order его обновляет)
        return obj.updated_at + timedelta(seconds=SHOP_ACCEPT_TIMEOUT_SECONDS)


class ShopOrderDetailSerializer(OrderDetailSerializer):
    pass


class ShopOrderAcceptSerializer(serializers.Serializer):
    eta_minutes = serializers.IntegerField(min_value=1, max_value=600)


class ShopOrderRejectSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=255)
