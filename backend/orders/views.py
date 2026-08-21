import uuid

from django.db import transaction
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from core.api import error_response

from .models import Order, OrderPhoto
from .permissions import IsShopStaff, get_staff_shop
from .serializers import (
    OrderCancelSerializer,
    OrderCreateSerializer,
    OrderDetailSerializer,
    OrderListSerializer,
    OrderPhotoRespondSerializer,
    ReviewCreateSerializer,
    ShopOrderAcceptSerializer,
    ShopOrderDetailSerializer,
    ShopOrderListSerializer,
    ShopOrderPhotoUploadSerializer,
    ShopOrderRejectSerializer,
)
from .services import OrderError, cancel_order_by_client, create_order, transition_order
from .state_machine import OrderStatus

CLIENT_ACTIVE_STATUSES = (
    OrderStatus.CREATED, OrderStatus.PAID, OrderStatus.SHOP_PENDING,
    OrderStatus.ACCEPTED, OrderStatus.PREPARING, OrderStatus.READY,
    OrderStatus.COURIER_ASSIGNED, OrderStatus.PICKED_UP, OrderStatus.ON_THE_WAY,
    OrderStatus.ARRIVED,
)
SHOP_ACTIVE_STATUSES = (
    OrderStatus.ACCEPTED, OrderStatus.PREPARING, OrderStatus.READY,
    OrderStatus.COURIER_ASSIGNED, OrderStatus.PICKED_UP, OrderStatus.ON_THE_WAY,
    OrderStatus.ARRIVED,
)


def _order_error_response(exc: OrderError) -> Response:
    return error_response(exc.code, exc.message, exc.http_status, exc.details)


# ================= клиент =================

class OrderListCreateView(APIView):
    """GET /orders/ (?status=active|history); POST /orders/ — создание (api.md §3)."""

    def get(self, request):
        qs = Order.objects.filter(client=request.user).select_related("shop")
        status_filter = request.query_params.get("status")
        if status_filter == "active":
            qs = qs.filter(status__in=CLIENT_ACTIVE_STATUSES)
        elif status_filter == "history":
            qs = qs.exclude(status__in=CLIENT_ACTIVE_STATUSES)
        paginator = PageNumberPagination()
        page = paginator.paginate_queryset(qs, request)
        serializer = OrderListSerializer(page, many=True)
        return paginator.get_paginated_response(serializer.data)

    def post(self, request):
        key_raw = request.headers.get("Idempotency-Key")
        idempotency_key = None
        if key_raw:
            try:
                idempotency_key = uuid.UUID(key_raw)
            except ValueError:
                return error_response(
                    "idempotency_key_invalid",
                    "Idempotency-Key должен быть UUID",
                    status.HTTP_400_BAD_REQUEST,
                )
        serializer = OrderCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            order, created = create_order(
                request.user, serializer.validated_data, idempotency_key
            )
        except OrderError as exc:
            return _order_error_response(exc)
        payload = {
            "id": order.id,
            "number": order.number,
            "status": order.status,
            "total": str(order.total),
            "payment": None,  # платёж инициируется отдельно: POST /orders/{id}/pay/
        }
        return Response(
            payload, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK
        )


class OrderDetailView(APIView):
    """GET /orders/{id}/ — позиции, история статусов, PIN, суммы."""

    def get(self, request, pk):
        order = (
            Order.objects.filter(pk=pk, client=request.user)
            .select_related("shop", "delivery")
            .prefetch_related("items", "status_history", "photos")
            .first()
        )
        if order is None:
            return error_response("not_found", "Заказ не найден", status.HTTP_404_NOT_FOUND)
        return Response(OrderDetailSerializer(order, context={"request": request}).data)


class OrderCancelView(APIView):
    """POST /orders/{id}/cancel/ — отмена клиентом (правила возврата api.md §3)."""

    def post(self, request, pk):
        order = Order.objects.filter(pk=pk, client=request.user).first()
        if order is None:
            return error_response("not_found", "Заказ не найден", status.HTTP_404_NOT_FOUND)
        serializer = OrderCancelSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            refund_amount = cancel_order_by_client(
                order, request.user, serializer.validated_data.get("reason", "")
            )
        except OrderError as exc:
            return _order_error_response(exc)
        return Response(
            {
                "id": order.id,
                "status": order.status,
                "refund_amount": str(refund_amount) if refund_amount is not None else None,
            }
        )


class OrderPhotoRespondView(APIView):
    """POST /orders/{id}/photo/respond/ {approved} — реакция клиента на фото букета."""

    def post(self, request, pk):
        order = Order.objects.filter(pk=pk, client=request.user).first()
        if order is None:
            return error_response("not_found", "Заказ не найден", status.HTTP_404_NOT_FOUND)
        serializer = OrderPhotoRespondSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        photo = order.photos.order_by("-id").first()
        if photo is None or photo.approved is not None:
            return error_response(
                "invalid_state",
                "Нет фото, ожидающего ответа",
                status.HTTP_409_CONFLICT,
            )
        approved = serializer.validated_data["approved"]
        photo.approved = approved
        photo.save(update_fields=["approved"])
        # WS магазину: букет одобрен / нужно переделать
        from core import ws_events

        ws_events.notify_shop_photo_response(order, approved)
        return Response({"id": photo.id, "approved": approved})


class OrderReviewView(APIView):
    """POST /orders/{id}/review/ — отзыв после delivered (api.md §3)."""

    def post(self, request, pk):
        from decimal import Decimal

        from reviews.models import Review

        order = Order.objects.filter(pk=pk, client=request.user).first()
        if order is None:
            return error_response("not_found", "Заказ не найден", status.HTTP_404_NOT_FOUND)
        if order.status not in (OrderStatus.DELIVERED, OrderStatus.COMPLETED):
            return error_response(
                "invalid_state",
                "Отзыв можно оставить только после доставки",
                status.HTTP_409_CONFLICT,
            )
        if hasattr(order, "review"):
            return error_response(
                "already_reviewed", "Отзыв уже оставлен", status.HTTP_409_CONFLICT
            )
        serializer = ReviewCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        with transaction.atomic():
            review = Review.objects.create(
                order=order,
                client=request.user,
                shop=order.shop,
                shop_rating=data["shop_rating"],
                courier_rating=data.get("courier_rating"),
                text=data.get("text", ""),
            )
            # денормализация рейтинга магазина
            shop = order.shop
            total_rating = shop.rating_avg * shop.rating_count + data["shop_rating"]
            shop.rating_count += 1
            shop.rating_avg = (total_rating / shop.rating_count).quantize(Decimal("0.01"))
            shop.save(update_fields=["rating_avg", "rating_count", "updated_at"])
        return Response({"id": review.id}, status=status.HTTP_201_CREATED)


# ================= панель магазина (api.md §5) =================

class ShopOrderListView(ListAPIView):
    """GET /shop/orders/ (?status=pending|active|history), скоуп — свой магазин."""

    permission_classes = (IsShopStaff,)
    serializer_class = ShopOrderListSerializer

    def get_queryset(self):
        qs = Order.objects.filter(shop=get_staff_shop(self.request.user))
        status_filter = self.request.query_params.get("status", "pending")
        if status_filter == "pending":
            qs = qs.filter(status=OrderStatus.SHOP_PENDING)
        elif status_filter == "active":
            qs = qs.filter(status__in=SHOP_ACTIVE_STATUSES)
        elif status_filter == "history":
            qs = qs.exclude(
                status__in=(OrderStatus.SHOP_PENDING,) + SHOP_ACTIVE_STATUSES
            )
        return qs


class _ShopOrderBaseView(APIView):
    permission_classes = (IsShopStaff,)

    def get_order(self, request, pk):
        return Order.objects.filter(pk=pk, shop=get_staff_shop(request.user)).first()

    def _not_found(self):
        return error_response("not_found", "Заказ не найден", status.HTTP_404_NOT_FOUND)


class ShopOrderDetailView(_ShopOrderBaseView):
    """GET /shop/orders/{id}/ — recipient_phone скрыт до accepted."""

    def get(self, request, pk):
        order = self.get_order(request, pk)
        if order is None:
            return self._not_found()
        data = ShopOrderDetailSerializer(order, context={"request": request}).data
        if order.status == OrderStatus.SHOP_PENDING:
            data["recipient_phone"] = None  # защита от увода клиентов (api.md §5)
        return Response(data)


class ShopOrderAcceptView(_ShopOrderBaseView):
    """POST /shop/orders/{id}/accept/ {eta_minutes} → accepted (затем preparing)."""

    def post(self, request, pk):
        order = self.get_order(request, pk)
        if order is None:
            return self._not_found()
        serializer = ShopOrderAcceptSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        eta = serializer.validated_data["eta_minutes"]
        if order.status != OrderStatus.SHOP_PENDING:
            return error_response(
                "invalid_state",
                f"Заказ в статусе «{order.status}», принять нельзя",
                status.HTTP_409_CONFLICT,
            )
        with transaction.atomic():
            transition_order(order, OrderStatus.ACCEPTED, actor=request.user)
            transition_order(
                order, OrderStatus.PREPARING, actor=request.user,
                comment=f"ETA сборки: {eta} мин",
            )
            # принятие сбрасывает штрафной счётчик таймаутов
            shop = order.shop
            if shop.consecutive_timeouts:
                shop.consecutive_timeouts = 0
                shop.save(update_fields=["consecutive_timeouts", "updated_at"])
        # WS + push клиенту о смене статуса (api.md §7)
        from core import ws_events
        from core.push import send_push

        ws_events.notify_order_status(order)
        send_push(
            order.client, "order_status",
            {"order_id": order.id, "status": order.status},
        )
        return Response({"id": order.id, "status": order.status})


class ShopOrderRejectView(_ShopOrderBaseView):
    """POST /shop/orders/{id}/reject/ {reason} → rejected + авто-возврат."""

    def post(self, request, pk):
        from payments.services import create_auto_refund

        from .services import release_promo

        order = self.get_order(request, pk)
        if order is None:
            return self._not_found()
        serializer = ShopOrderRejectSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data["reason"]
        if order.status != OrderStatus.SHOP_PENDING:
            return error_response(
                "invalid_state",
                f"Заказ в статусе «{order.status}», отклонить нельзя",
                status.HTTP_409_CONFLICT,
            )
        with transaction.atomic():
            payment = order.payments.filter(status="success").first()
            if payment is not None:
                create_auto_refund(payment, payment.amount, f"Отклонено магазином: {reason}")
            order.cancel_reason = reason
            order.save(update_fields=["cancel_reason", "updated_at"])
            transition_order(order, OrderStatus.REJECTED, actor=request.user, comment=reason)
            release_promo(order)
        # WS + push: клиенту — отказ (предложить другой магазин), панели — order_cancelled
        from core import ws_events
        from core.push import send_push

        ws_events.notify_order_status(order)
        ws_events.notify_shop_order_cancelled(order)
        send_push(
            order.client, "order_rejected",
            {"order_id": order.id, "reason": reason},
        )
        return Response({"id": order.id, "status": order.status})


class ShopOrderPhotoUploadView(_ShopOrderBaseView):
    """POST /shop/orders/{id}/photo/ — фото собранного букета на одобрение клиенту
    (multipart image; только accepted..ready)."""

    PHOTO_STATUSES = (
        OrderStatus.ACCEPTED, OrderStatus.PREPARING, OrderStatus.READY,
    )

    def post(self, request, pk):
        order = self.get_order(request, pk)
        if order is None:
            return self._not_found()
        if order.status not in self.PHOTO_STATUSES:
            return error_response(
                "invalid_state",
                f"Фото можно отправить, пока заказ в сборке (сейчас «{order.status}»)",
                status.HTTP_409_CONFLICT,
            )
        serializer = ShopOrderPhotoUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        photo = OrderPhoto.objects.create(
            order=order, image=serializer.validated_data["image"], approved=None
        )
        url = request.build_absolute_uri(photo.image.url)
        # WS + push клиенту: пришло фото букета (api.md §5, §7)
        from core import ws_events
        from core.push import send_push

        ws_events.notify_bouquet_photo(order, url)
        send_push(
            order.client, "bouquet_photo",
            {"order_id": order.id, "photo_url": url},
        )
        return Response(
            {"id": photo.id, "url": url, "approved": photo.approved},
            status=status.HTTP_201_CREATED,
        )


class ShopOrderReadyView(_ShopOrderBaseView):
    """POST /shop/orders/{id}/ready/ → ready (триггер назначения курьера)."""

    def post(self, request, pk):
        order = self.get_order(request, pk)
        if order is None:
            return self._not_found()
        if order.status != OrderStatus.PREPARING:
            return error_response(
                "invalid_state",
                f"Заказ в статусе «{order.status}», готовность нельзя отметить",
                status.HTTP_409_CONFLICT,
            )
        transition_order(order, OrderStatus.READY, actor=request.user)
        # WS + push: клиенту — статус, онлайн-курьерам — заказ доступен (api.md §6, §7)
        from core import ws_events
        from core.push import send_push, send_push_many
        from delivery.models import CourierProfile

        ws_events.notify_order_status(order)
        ws_events.notify_couriers_order_available(order)
        send_push(
            order.client, "order_status",
            {"order_id": order.id, "status": order.status},
        )
        send_push_many(
            [
                p.user
                for p in CourierProfile.objects.filter(
                    status=CourierProfile.Status.ONLINE
                ).select_related("user")
            ],
            "order_available",
            {"order_id": order.id},
        )
        return Response({"id": order.id, "status": order.status})
