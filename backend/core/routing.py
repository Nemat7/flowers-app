from django.urls import path

from .consumers import ClientOrderConsumer, CourierConsumer, ShopConsumer

websocket_urlpatterns = [
    path("ws/client/orders/<int:order_id>/", ClientOrderConsumer.as_asgi()),
    path("ws/shop/", ShopConsumer.as_asgi()),
    path("ws/courier/", CourierConsumer.as_asgi()),
]
