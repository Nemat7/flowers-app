"""API курьера (api.md §6). JWT, роль courier (IsCourier — есть CourierProfile)."""
from datetime import timedelta
from decimal import Decimal

from django.db.models import Sum
from django.utils import timezone
from rest_framework import status
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from core.api import error_response
from orders.state_machine import OrderStatus

from .models import CourierProfile, Delivery
from .permissions import IsCourier
from .serializers import (
    CourierOrderSerializer,
    CourierStatusSerializer,
    LocationBatchSerializer,
)
from .services import (
    DeliveryError,
    accept_order,
    arrive_order,
    available_orders,
    complete_order,
    get_active_delivery,
    pickup_order,
    set_courier_status,
    submit_locations,
)

FINISHED_ORDER_STATUSES = (OrderStatus.DELIVERED, OrderStatus.COMPLETED)


def _delivery_error_response(exc: DeliveryError) -> Response:
    return error_response(exc.code, exc.message, exc.http_status, exc.details)


def _serialize_order(request, order):
    return CourierOrderSerializer(
        order, context={"courier_point": request.user.courier_profile.current_point}
    ).data


class _CourierBaseView(APIView):
    permission_classes = (IsCourier,)

    @property
    def profile(self) -> CourierProfile:
        return self.request.user.courier_profile


class CourierStatusView(_CourierBaseView):
    """GET /courier/status/ — текущий статус; PATCH {status: online|offline} — выход на линию."""

    def get(self, request):
        return Response({"status": self.profile.status})

    def patch(self, request):
        serializer = CourierStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            profile = set_courier_status(
                self.profile, serializer.validated_data["status"]
            )
        except DeliveryError as exc:
            return _delivery_error_response(exc)
        return Response({"status": profile.status})


class CourierCurrentOrderView(_CourierBaseView):
    """GET /courier/orders/current/ — активный заказ (один за раз)."""

    def get(self, request):
        delivery = get_active_delivery(self.profile)
        if delivery is None:
            return Response({"order": None})
        return Response({"order": _serialize_order(request, delivery.order)})


class CourierAvailableOrdersView(_CourierBaseView):
    """GET /courier/orders/available/ — заказы ready без курьера."""

    def get(self, request):
        orders = available_orders()
        return Response(
            [_serialize_order(request, order) for order in orders]
        )


class _CourierOrderActionView(_CourierBaseView):
    def post(self, request, pk):
        try:
            order = self.act(self.profile, pk, request)
        except DeliveryError as exc:
            return _delivery_error_response(exc)
        return Response({"id": order.id, "status": order.status})

    def act(self, profile, pk, request):  # pragma: no cover - переопределяется
        raise NotImplementedError


class CourierOrderAcceptView(_CourierOrderActionView):
    """POST /courier/orders/{id}/accept/ — взять заказ → courier_assigned."""

    def act(self, profile, pk, request):
        return accept_order(profile, pk)


class CourierOrderPickupView(_CourierOrderActionView):
    """POST /courier/orders/{id}/pickup/ → picked_up → on_the_way."""

    def act(self, profile, pk, request):
        return pickup_order(profile, pk)


class CourierOrderArriveView(_CourierOrderActionView):
    """POST /courier/orders/{id}/arrive/ → arrived."""

    def act(self, profile, pk, request):
        return arrive_order(profile, pk)


class CourierOrderCompleteView(_CourierBaseView):
    """POST /courier/orders/{id}/complete/ — {pin} или {photo} → delivered."""

    def post(self, request, pk):
        pin = request.data.get("pin")
        photo = request.FILES.get("photo")
        try:
            order = complete_order(self.profile, pk, pin=pin, photo=photo)
        except DeliveryError as exc:
            return _delivery_error_response(exc)
        return Response({"id": order.id, "status": order.status})


class CourierLocationView(_CourierBaseView):
    """POST /courier/location/ — {points:[{lat,lng,ts}]} батч GPS."""

    def post(self, request):
        serializer = LocationBatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            result = submit_locations(self.profile, serializer.validated_data["points"])
        except DeliveryError as exc:
            return _delivery_error_response(exc)
        return Response(result)


class CourierEarningsView(_CourierBaseView):
    """GET /courier/earnings/ — заработок: сегодня/неделя/всего (sum fee по delivered+completed)."""

    def get(self, request):
        qs = Delivery.objects.filter(
            courier=self.profile, order__status__in=FINISHED_ORDER_STATUSES
        )
        now = timezone.localtime()
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        week_start = today_start - timedelta(days=now.weekday())

        def _sum(since=None):
            filtered = qs if since is None else qs.filter(delivered_at__gte=since)
            return filtered.aggregate(total=Sum("fee"))["total"] or Decimal("0.00")

        return Response(
            {
                "today": str(_sum(today_start)),
                "week": str(_sum(week_start)),
                "total": str(_sum()),
            }
        )


class CourierOrdersHistoryView(_CourierBaseView):
    """GET /courier/orders/history/ — завершённые доставки (пагинация)."""

    def get(self, request):
        qs = (
            Delivery.objects.filter(
                courier=self.profile, order__status__in=FINISHED_ORDER_STATUSES
            )
            .select_related("order", "order__shop")
            .order_by("-delivered_at")
        )
        paginator = PageNumberPagination()
        page = paginator.paginate_queryset(qs, request)
        results = []
        for delivery in page:
            item = _serialize_order(request, delivery.order)
            item["delivered_at"] = delivery.delivered_at
            results.append(item)
        return paginator.get_paginated_response(results)
