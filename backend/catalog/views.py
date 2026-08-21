from django.contrib.gis.db.models.functions import Distance
from django.contrib.gis.geos import Point
from django.contrib.gis.measure import D
from django.db import transaction
from django.db.models import OuterRef, Q, Subquery
from rest_framework import generics, status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from core.api import error_response
from orders.permissions import IsShopStaff, get_staff_shop

from .models import Category, Product, ProductPhoto, Shop, ShopWorkingHours
from .serializers import (
    CategorySerializer,
    ProductDetailSerializer,
    ProductListSerializer,
    ProductPhotoSerializer,
    ProductPhotoUploadSerializer,
    ShopDetailSerializer,
    ShopListSerializer,
    ShopProductSerializer,
    WorkingHoursInputSerializer,
    WorkingHoursSerializer,
)
from .services import is_shop_open


def _request_point(request) -> Point | None:
    """?lat&lng → Point(lng, lat) SRID 4326; None, если координат нет."""
    lat, lng = request.query_params.get("lat"), request.query_params.get("lng")
    if lat is None or lng is None:
        return None
    try:
        return Point(float(lng), float(lat), srid=4326)
    except (TypeError, ValueError):
        raise ValidationError({"lat/lng": "Некорректные координаты"})


def _shop_kind_subquery():
    """Категория товаров магазина для подписи на карточке главной («Цветы»)."""
    return (
        Product.objects.filter(
            shop=OuterRef("pk"), is_active=True, is_available=True
        )
        .order_by("category__sort_order", "sort_order")
        .values("category__name")[:1]
    )


class CategoryListView(generics.ListAPIView):
    """GET /categories/ — категории каталога."""

    serializer_class = CategorySerializer
    pagination_class = None
    queryset = Category.objects.filter(is_active=True)


class ShopListView(generics.ListAPIView):
    """GET /shops/ — только approved и не скрытые; ?lat&lng — сортировка по расстоянию."""

    serializer_class = ShopListSerializer

    def get_queryset(self):
        qs = (
            Shop.objects.filter(status=Shop.Status.APPROVED, is_hidden=False)
            .prefetch_related("working_hours", "zones")
            .annotate(kind_name=Subquery(_shop_kind_subquery()))
        )
        point = _request_point(self.request)
        if point is not None:
            qs = qs.filter(point__distance_lte=(point, D(km=100))).annotate(
                distance=Distance("point", point)
            ).order_by("distance")
        else:
            qs = qs.order_by("-rating_avg", "-rating_count", "id")

        q = self.request.query_params.get("q")
        if q:
            qs = qs.filter(Q(name__icontains=q) | Q(description__icontains=q))
        if self.request.query_params.get("open_now") == "1":
            qs = [s for s in qs if is_shop_open(s)]
        return qs


class ShopDetailView(generics.RetrieveAPIView):
    """GET /shops/{id}/ — часы работы, зоны, card_price, min_order, рейтинг."""

    serializer_class = ShopDetailSerializer

    def get_queryset(self):
        return (
            Shop.objects.filter(status=Shop.Status.APPROVED)
            .prefetch_related("working_hours", "zones")
            .annotate(kind_name=Subquery(_shop_kind_subquery()))
        )


class ProductListView(generics.ListAPIView):
    """GET /products/ — фильтры shop_id/category/q/price_min/price_max/tag/available."""

    serializer_class = ProductListSerializer

    def get_queryset(self):
        qs = Product.objects.filter(
            is_active=True, shop__status=Shop.Status.APPROVED
        ).select_related("shop", "category").prefetch_related("photos")

        params = self.request.query_params
        if params.get("shop_id"):
            qs = qs.filter(shop_id=params["shop_id"])
        if params.get("category"):
            qs = qs.filter(
                Q(category__slug=params["category"])
                | Q(category_id=params["category"] if params["category"].isdigit() else None)
            )
        if params.get("q"):
            qs = qs.filter(
                Q(name__icontains=params["q"])
                | Q(description__icontains=params["q"])
                | Q(composition__icontains=params["q"])
            )
        if params.get("price_min"):
            qs = qs.filter(price__gte=params["price_min"])
        if params.get("price_max"):
            qs = qs.filter(price__lte=params["price_max"])
        if params.get("tag"):
            qs = qs.filter(tags__contains=[params["tag"]])
        # лента «Наше фирменное» на главной (макет v5 01-home)
        if params.get("featured") == "1":
            qs = qs.filter(is_featured=True)
        # по умолчанию только доступные (api.md §2)
        if params.get("available", "1") == "1":
            qs = qs.filter(is_available=True)
        return qs.order_by("sort_order", "id")


class ProductDetailView(generics.RetrieveAPIView):
    """GET /products/{id}/ — карточка товара с фото, составом, магазином."""

    serializer_class = ProductDetailSerializer
    queryset = Product.objects.filter(
        is_active=True, shop__status=Shop.Status.APPROVED
    ).select_related("shop", "category").prefetch_related("photos")


# ================= панель магазина (api.md §5) =================

MAX_PRODUCT_PHOTOS = 5  # до 5 фото на товар


class _ShopScopedView(APIView):
    """База для endpoint'ов панели: скоуп по магазину сотрудника."""

    permission_classes = (IsShopStaff,)

    @property
    def shop(self) -> Shop:
        return get_staff_shop(self.request.user)

    def get_product(self, pk) -> Product | None:
        return Product.objects.filter(pk=pk, shop=self.shop).first()

    @staticmethod
    def _product_not_found():
        return error_response("not_found", "Товар не найден", status.HTTP_404_NOT_FOUND)


class ShopProductListCreateView(generics.ListCreateAPIView):
    """GET/POST /shop/products/ — товары своего магазина (включая архивные)."""

    permission_classes = (IsShopStaff,)
    serializer_class = ShopProductSerializer
    pagination_class = None  # панели нужен весь каталог магазина сразу

    def get_queryset(self):
        return (
            Product.objects.filter(shop=get_staff_shop(self.request.user))
            .select_related("category")
            .prefetch_related("photos")
            .order_by("sort_order", "id")
        )

    def perform_create(self, serializer):
        serializer.save(shop=get_staff_shop(self.request.user))


class ShopProductDetailView(generics.RetrieveUpdateDestroyAPIView):
    """PATCH/DELETE /shop/products/{id}/ — правка; DELETE = is_active=false."""

    permission_classes = (IsShopStaff,)
    serializer_class = ShopProductSerializer
    http_method_names = ("patch", "delete", "head", "options")

    def get_queryset(self):
        # скоуп по магазину → чужой товар даёт 404
        return Product.objects.filter(shop=get_staff_shop(self.request.user))

    def perform_destroy(self, instance):
        # мягкое удаление (api.md §5): товар уходит в архив, снимки в заказах живы
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])


class ShopProductToggleAvailableView(_ShopScopedView):
    """POST /shop/products/{id}/toggle-available/ — выключатель «в наличии», один тап."""

    def post(self, request, pk):
        product = self.get_product(pk)
        if product is None:
            return self._product_not_found()
        product.is_available = not product.is_available
        product.save(update_fields=["is_available", "updated_at"])
        return Response({"id": product.id, "is_available": product.is_available})


class ShopProductPhotosView(_ShopScopedView):
    """POST /shop/products/{id}/photos/ — добавить фото (multipart, лимит 5 на товар)."""

    def post(self, request, pk):
        product = self.get_product(pk)
        if product is None:
            return self._product_not_found()
        files = request.FILES.getlist("photos") or request.FILES.getlist("photo")
        if not files:
            return error_response(
                "no_file", "Передайте файл(ы) в поле photos", status.HTTP_400_BAD_REQUEST
            )
        current = product.photos.count()
        if current + len(files) > MAX_PRODUCT_PHOTOS:
            return error_response(
                "photo_limit",
                f"Не больше {MAX_PRODUCT_PHOTOS} фото на товар (уже {current})",
                status.HTTP_400_BAD_REQUEST,
            )
        next_order = (product.photos.last().sort_order + 1) if current else 0
        created = []
        for file in files:
            serializer = ProductPhotoUploadSerializer(data={"image": file})
            serializer.is_valid(raise_exception=True)
            created.append(
                ProductPhoto.objects.create(
                    product=product,
                    image=serializer.validated_data["image"],
                    sort_order=next_order,
                )
            )
            next_order += 1
        return Response(
            ProductPhotoSerializer(created, many=True).data,
            status=status.HTTP_201_CREATED,
        )


class ShopProductPhotoDeleteView(_ShopScopedView):
    """DELETE /shop/products/{id}/photos/{photo_id}/ — удалить фото товара."""

    def delete(self, request, pk, photo_id):
        photo = ProductPhoto.objects.filter(
            pk=photo_id, product_id=pk, product__shop=self.shop
        ).first()
        if photo is None:
            return error_response(
                "not_found", "Фото не найдено", status.HTTP_404_NOT_FOUND
            )
        photo.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class ShopHoursView(_ShopScopedView):
    """GET/PUT /shop/hours/ — часы работы по дням недели; PUT — массив 7 дней (upsert)."""

    def get(self, request):
        hours = self.shop.working_hours.all().order_by("weekday")
        return Response(WorkingHoursSerializer(hours, many=True).data)

    def put(self, request):
        serializer = WorkingHoursInputSerializer(data=request.data, many=True)
        serializer.is_valid(raise_exception=True)
        days = serializer.validated_data
        weekdays = [d["weekday"] for d in days]
        if len(days) != 7 or sorted(weekdays) != list(range(7)):
            return error_response(
                "invalid_days",
                "Нужен массив всех 7 дней недели (weekday 0–6, по одному разу)",
                status.HTTP_400_BAD_REQUEST,
            )
        with transaction.atomic():
            for day in days:
                ShopWorkingHours.objects.update_or_create(
                    shop=self.shop,
                    weekday=day["weekday"],
                    defaults={
                        "open_time": day["open_time"],
                        "close_time": day["close_time"],
                        "is_day_off": day["is_day_off"],
                    },
                )
        hours = self.shop.working_hours.all().order_by("weekday")
        return Response(WorkingHoursSerializer(hours, many=True).data)
