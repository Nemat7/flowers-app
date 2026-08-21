"""Тесты панели магазина: каталог (товары, фото) и часы работы (api.md §5)."""
import base64
from datetime import time

from django.core.files.uploadedfile import SimpleUploadedFile

from catalog.models import Product, ProductPhoto, Shop, ShopWorkingHours
from marketing.models import Banner
from orders.tests import LAT, LNG, BaseFlowersTestCase

SHOP_PRODUCTS_URL = "/api/v1/shop/products/"
SHOP_HOURS_URL = "/api/v1/shop/hours/"

# 1x1 PNG для multipart-загрузки фото
PNG_BYTES = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
    "+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)


def _png(name="photo.png"):
    return SimpleUploadedFile(name, PNG_BYTES, content_type="image/png")


class ShopProductTests(BaseFlowersTestCase):
    def setUp(self):
        super().setUp()
        self.as_staff()

    def test_list_own_products(self):
        response = self.api.get(SHOP_PRODUCTS_URL)
        self.assertEqual(response.status_code, 200, response.data)
        names = {p["name"] for p in response.data}
        self.assertEqual(names, {"Розы", "Тюльпаны"})
        # чужой магазин не попадает в список
        self.assertNotIn("Чужой", names)

    def test_client_forbidden(self):
        self.api.force_authenticate(self.client_user)
        for method in ("get", "post"):
            response = getattr(self.api, method)(SHOP_PRODUCTS_URL)
            self.assertEqual(response.status_code, 403, method)

    def test_create(self):
        response = self.api.post(
            SHOP_PRODUCTS_URL,
            {
                "name": "Пионы",
                "category": self.category.id,
                "price": "420.00",
                "composition": "7 пионов, упаковка",
                "description": "Сезонные пионы",
                "tags": ["romantic", "pink"],
                "sort_order": 5,
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        product = Product.objects.get(pk=response.data["id"])
        self.assertEqual(product.shop, self.shop)
        self.assertEqual(product.tags, ["romantic", "pink"])
        self.assertTrue(product.is_available)
        self.assertTrue(product.is_active)
        self.assertEqual(response.data["category_name"], "Букеты")

    def test_create_foreign_category_ok_but_required(self):
        response = self.api.post(
            SHOP_PRODUCTS_URL, {"name": "Без категории", "price": "10.00"}, format="json"
        )
        self.assertEqual(response.status_code, 400)

    def test_patch(self):
        response = self.api.patch(
            f"{SHOP_PRODUCTS_URL}{self.product.id}/",
            {"price": "399.00", "name": "Розы красные"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.product.refresh_from_db()
        self.assertEqual(str(self.product.price), "399.00")
        self.assertEqual(self.product.name, "Розы красные")

    def test_delete_is_soft(self):
        response = self.api.delete(f"{SHOP_PRODUCTS_URL}{self.product.id}/")
        self.assertEqual(response.status_code, 204)
        self.product.refresh_from_db()
        self.assertFalse(self.product.is_active)
        # в списке магазина архивный товар остаётся (приглушённый)
        names = {p["name"] for p in self.api.get(SHOP_PRODUCTS_URL).data}
        self.assertIn("Розы", names)
        # из публичного каталога исчезает
        public = self.api.get(f"/api/v1/products/?shop_id={self.shop.id}&available=0")
        public_names = {p["name"] for p in public.data["results"]}
        self.assertNotIn("Розы", public_names)

    def test_foreign_shop_product_404(self):
        foreign = self.foreign_product
        responses = [
            self.api.patch(
                f"{SHOP_PRODUCTS_URL}{foreign.id}/", {"price": "1.00"}, format="json"
            ),
            self.api.delete(f"{SHOP_PRODUCTS_URL}{foreign.id}/"),
            self.api.post(f"{SHOP_PRODUCTS_URL}{foreign.id}/toggle-available/", {}),
            self.api.post(f"{SHOP_PRODUCTS_URL}{foreign.id}/photos/", {"photos": _png()}),
        ]
        for response in responses:
            self.assertEqual(response.status_code, 404)

    def test_toggle_available(self):
        url = f"{SHOP_PRODUCTS_URL}{self.product.id}/toggle-available/"
        response = self.api.post(url, {})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            response.data, {"id": self.product.id, "is_available": False}
        )
        self.product.refresh_from_db()
        self.assertFalse(self.product.is_available)

        response = self.api.post(url, {})
        self.assertEqual(response.data["is_available"], True)
        self.product.refresh_from_db()
        self.assertTrue(self.product.is_available)

    def test_photos_upload_limit_and_delete(self):
        url = f"{SHOP_PRODUCTS_URL}{self.product.id}/photos/"
        # пакетная загрузка трёх фото
        response = self.api.post(
            url, {"photos": [_png("a.png"), _png("b.png"), _png("c.png")]}
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(len(response.data), 3)
        self.assertEqual(self.product.photos.count(), 3)

        # ещё два — впритык к лимиту 5
        response = self.api.post(url, {"photos": [_png("d.png"), _png("e.png")]})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.product.photos.count(), 5)

        # шестое — отказ
        response = self.api.post(url, {"photos": _png("f.png")})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "photo_limit")
        self.assertEqual(self.product.photos.count(), 5)

        # удаление одного — снова можно загрузить
        photo_id = self.product.photos.first().id
        response = self.api.delete(
            f"{SHOP_PRODUCTS_URL}{self.product.id}/photos/{photo_id}/"
        )
        self.assertEqual(response.status_code, 204)
        self.assertEqual(self.product.photos.count(), 4)
        response = self.api.post(url, {"photos": _png("g.png")})
        self.assertEqual(response.status_code, 201)

    def test_photo_upload_rejects_non_image(self):
        bad = SimpleUploadedFile("x.txt", b"not an image", content_type="text/plain")
        response = self.api.post(
            f"{SHOP_PRODUCTS_URL}{self.product.id}/photos/", {"photos": bad}
        )
        self.assertEqual(response.status_code, 400)

    def test_photo_delete_foreign_404(self):
        photo = ProductPhoto.objects.create(product=self.foreign_product, image=_png())
        response = self.api.delete(
            f"{SHOP_PRODUCTS_URL}{self.foreign_product.id}/photos/{photo.id}/"
        )
        self.assertEqual(response.status_code, 404)


class ShopHoursTests(BaseFlowersTestCase):
    def setUp(self):
        super().setUp()
        self.as_staff()

    @staticmethod
    def _days(**overrides):
        days = [
            {
                "weekday": weekday,
                "open_time": "09:00",
                "close_time": "21:00",
                "is_day_off": False,
            }
            for weekday in range(7)
        ]
        for key, value in overrides.items():
            days[int(key)].update(value)
        return days

    def test_get_returns_saved_days(self):
        response = self.api.get(SHOP_HOURS_URL)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data), 7)
        self.assertEqual(response.data[0]["weekday"], 0)

    def test_put_upserts_all_seven_days(self):
        days = self._days(**{"6": {"is_day_off": True}})
        response = self.api.put(SHOP_HOURS_URL, days, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        # upsert: дублей нет, строк ровно 7
        self.assertEqual(
            ShopWorkingHours.objects.filter(shop=self.shop).count(), 7
        )
        sunday = ShopWorkingHours.objects.get(shop=self.shop, weekday=6)
        self.assertTrue(sunday.is_day_off)
        monday = ShopWorkingHours.objects.get(shop=self.shop, weekday=0)
        self.assertEqual(monday.open_time, time(9, 0))
        self.assertEqual(monday.close_time, time(21, 0))
        # GET отдаёт то, что сохранили
        got = self.api.get(SHOP_HOURS_URL).data
        self.assertEqual(len(got), 7)
        self.assertTrue(got[6]["is_day_off"])

    def test_put_requires_exactly_seven_unique_days(self):
        response = self.api.put(SHOP_HOURS_URL, self._days()[:6], format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "invalid_days")

        days = self._days()
        days[6]["weekday"] = 5  # дубликат, воскресенья нет
        response = self.api.put(SHOP_HOURS_URL, days, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["error"]["code"], "invalid_days")

    def test_put_validates_weekday_and_time(self):
        days = self._days()
        days[0]["weekday"] = 7
        response = self.api.put(SHOP_HOURS_URL, days, format="json")
        self.assertEqual(response.status_code, 400)

        days = self._days()
        days[0]["open_time"] = "25:00"
        response = self.api.put(SHOP_HOURS_URL, days, format="json")
        self.assertEqual(response.status_code, 400)

    def test_client_forbidden(self):
        self.api.force_authenticate(self.client_user)
        self.assertEqual(self.api.get(SHOP_HOURS_URL).status_code, 403)
        self.assertEqual(
            self.api.put(SHOP_HOURS_URL, self._days(), format="json").status_code, 403
        )


class HomeScreenApiTests(BaseFlowersTestCase):
    """Данные главного экрана клиента (макет v5 01-home)."""

    def setUp(self):
        super().setUp()
        self.api.force_authenticate(self.client_user)

    def test_shop_card_fields(self):
        """Карточка магазина: обложка, «наш магазин», профиль и тариф доставки."""
        self.shop.is_own = True
        self.shop.save(update_fields=["is_own"])

        response = self.api.get("/api/v1/shops/", {"lat": LAT, "lng": LNG})
        self.assertEqual(response.status_code, 200, response.data)
        card = next(s for s in response.data["results"] if s["id"] == self.shop.id)

        self.assertTrue(card["is_own"])
        self.assertIn("cover_photo", card)
        # профиль магазина берётся из категории его товаров
        self.assertEqual(card["kind"], "Букеты")
        # «Доставка от 10 с.» — минимальная база по зонам магазина
        self.assertEqual(float(card["delivery_fee_from"]), 10.0)

    def test_kind_none_when_shop_has_no_products(self):
        empty_shop = Shop.objects.create(
            name="Пустой", point=self.shop.point, address_text="—",
            status=Shop.Status.APPROVED,
        )
        response = self.api.get("/api/v1/shops/")
        card = next(s for s in response.data["results"] if s["id"] == empty_shop.id)
        self.assertIsNone(card["kind"])
        self.assertIsNone(card["delivery_fee_from"])

    def test_featured_filter(self):
        """?featured=1 отдаёт только ленту «Наше фирменное»."""
        self.product.is_featured = True
        self.product.save(update_fields=["is_featured"])

        response = self.api.get("/api/v1/products/", {"featured": "1"})
        self.assertEqual(response.status_code, 200, response.data)
        ids = [p["id"] for p in response.data["results"]]
        self.assertEqual(ids, [self.product.id])
        self.assertTrue(response.data["results"][0]["is_featured"])

        # без фильтра отдаются все товары
        response = self.api.get("/api/v1/products/")
        self.assertGreater(response.data["count"], 1)

    def test_banners(self):
        Banner.objects.create(
            title="−20% на первый заказ",
            tag="Акция",
            image="banners/promo.jpg",
            link_type=Banner.LinkType.PROMO,
            link_value="SPRING10",
            sort_order=0,
        )
        Banner.objects.create(
            title="Скрытый", image="banners/x.jpg",
            link_type=Banner.LinkType.URL, link_value="", is_active=False,
        )

        response = self.api.get("/api/v1/banners/")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["tag"], "Акция")
        self.assertEqual(response.data[0]["link_value"], "SPRING10")

    def test_category_image_in_list(self):
        self.category.image = "categories/bukety.jpg"
        self.category.save(update_fields=["image"])

        response = self.api.get("/api/v1/categories/")
        card = next(c for c in response.data if c["id"] == self.category.id)
        self.assertIn("categories/bukety.jpg", card["image"])
