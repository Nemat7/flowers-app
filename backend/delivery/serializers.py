from rest_framework import serializers

from core.ws_events import _haversine_m
from orders.models import Order


class CourierStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=("online", "offline"))


class LocationPointSerializer(serializers.Serializer):
    lat = serializers.FloatField(min_value=-90, max_value=90)
    lng = serializers.FloatField(min_value=-180, max_value=180)
    ts = serializers.FloatField()  # unixtime (секунды)


class LocationBatchSerializer(serializers.Serializer):
    points = serializers.ListField(
        child=LocationPointSerializer(), allow_empty=False, max_length=100
    )


class CourierOrderSerializer(serializers.ModelSerializer):
    """Карточка заказа для курьера: магазин, адрес, получатель, заработок."""

    shop = serializers.SerializerMethodField()
    address = serializers.SerializerMethodField()
    fee = serializers.SerializerMethodField()
    distance = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = (
            "id", "number", "status", "shop", "address",
            "recipient_name", "recipient_phone",
            "total", "delivery_fee", "fee", "distance", "created_at",
        )

    def get_shop(self, obj):
        shop = obj.shop
        return {
            "id": shop.id,
            "name": shop.name,
            "address_text": shop.address_text,
            "lat": shop.point.y if shop.point else None,
            "lng": shop.point.x if shop.point else None,
        }

    def get_address(self, obj):
        return {
            "lat": obj.delivery_point.y,
            "lng": obj.delivery_point.x,
            "address_text": obj.delivery_address_text,
            "details": obj.delivery_details,
        }

    def get_fee(self, obj):
        delivery = getattr(obj, "delivery", None)
        return str(delivery.fee) if delivery else None

    def get_distance(self, obj):
        """Дистанция от текущей позиции курьера (context['courier_point']) до магазина."""
        courier_point = self.context.get("courier_point")
        if courier_point is None or obj.shop.point is None:
            return None
        return _haversine_m(
            courier_point.y, courier_point.x, obj.shop.point.y, obj.shop.point.x
        )
