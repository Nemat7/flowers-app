"""seed_media — демо-картинки для главного экрана (макет v5 01-home).

Дополняет уже существующие данные, ничего не удаляя и не создавая магазинов:
обложки магазинам, картинки категориям, фото товарам без фото, пара баннеров,
отметки «наше фирменное». Заполняет только пустые поля — повторный запуск
безопасен; `--force` перезаписывает картинки заново.

Источник фото — backend/demo_assets/ (свободные лицензии, те же кадры, что в
макетах). Запуск: docker compose exec backend python manage.py seed_media
"""
from pathlib import Path

from django.core.files import File
from django.core.management.base import BaseCommand

from catalog.models import Category, Product, ProductPhoto, Shop
from marketing.models import Banner

ASSETS = Path(__file__).resolve().parents[3] / "demo_assets"

# кадры из макетов: b*/g* — цветы, s* — сладости
FLOWERS = ["b1.jpg", "b2.jpg", "g1.jpg", "g2.jpg", "b3.jpg", "g3.jpg", "b4.jpg", "g4.jpg"]
SWEETS = ["s1.jpg", "s2.jpg", "s3.jpg"]
CATEGORY_IMAGES = {
    "bukety": "b4.jpg",
    "kompozitsii": "g7.jpg",
    "sladosti": "s3.jpg",
    "otkrytki": "g6.jpg",
    "povody": "g7.jpg",
}
BANNERS = [
    ("−20% на первый заказ", "Акция", "g7.jpg", Banner.LinkType.PROMO, "SPRING10"),
    ("Бесплатно от 300 с.", "Доставка", "b6.jpg", Banner.LinkType.URL, ""),
]

SWEET_WORDS = ("сладост", "десерт", "торт", "конфет", "шоколад", "печен", "макарон")


def is_sweet(product: Product) -> bool:
    haystack = f"{product.category.name} {product.name}".lower()
    return any(word in haystack for word in SWEET_WORDS)


class Command(BaseCommand):
    help = "Заполнить демо-картинки главного экрана (обложки, категории, баннеры)"

    def add_arguments(self, parser):
        parser.add_argument(
            "--force", action="store_true",
            help="перезаписать картинки, даже если они уже заданы",
        )

    def handle(self, *args, **options):
        force = options["force"]
        if not ASSETS.is_dir():
            self.stderr.write(f"Нет папки с картинками: {ASSETS}")
            return

        self._covers(force)
        self._categories(force)
        self._product_photos(force)
        self._featured()
        self._banners(force)
        self._own_shop()

    def _save(self, field, filename: str, prefix: str) -> bool:
        path = ASSETS / filename
        if not path.is_file():
            self.stderr.write(f"Пропущен {filename}: файла нет")
            return False
        with path.open("rb") as fh:
            field.save(f"{prefix}-{filename}", File(fh), save=True)
        return True

    def _covers(self, force: bool):
        shops = Shop.objects.order_by("id")
        done = 0
        for index, shop in enumerate(shops):
            if shop.cover_photo and not force:
                continue
            if self._save(shop.cover_photo, FLOWERS[index % len(FLOWERS)], f"shop{shop.id}"):
                done += 1
        self.stdout.write(f"Обложки магазинов: {done}")

    def _categories(self, force: bool):
        done = 0
        for category in Category.objects.all():
            if category.image and not force:
                continue
            filename = CATEGORY_IMAGES.get(category.slug, FLOWERS[category.id % len(FLOWERS)])
            if self._save(category.image, filename, f"cat{category.id}"):
                done += 1
        self.stdout.write(f"Картинки категорий: {done}")

    def _product_photos(self, force: bool):
        done = 0
        products = Product.objects.select_related("category").order_by("id")
        for index, product in enumerate(products):
            if product.photos.exists() and not force:
                continue
            pool = SWEETS if is_sweet(product) else FLOWERS
            path = ASSETS / pool[index % len(pool)]
            if not path.is_file():
                continue
            photo = ProductPhoto(product=product, sort_order=0)
            with path.open("rb") as fh:
                photo.image.save(f"product{product.id}-{path.name}", File(fh), save=False)
            photo.save()
            done += 1
        self.stdout.write(f"Фото товаров: {done}")

    def _featured(self):
        """«Наше фирменное» — первые товары своих магазинов, если ничего не отмечено."""
        if Product.objects.filter(is_featured=True).exists():
            self.stdout.write("Фирменные товары: уже отмечены, не трогаю")
            return
        ids = list(
            Product.objects.filter(is_active=True, is_available=True)
            .order_by("shop_id", "sort_order", "id")
            .values_list("id", flat=True)[:6]
        )
        Product.objects.filter(id__in=ids).update(is_featured=True)
        self.stdout.write(f"Фирменные товары: {len(ids)}")

    def _banners(self, force: bool):
        if Banner.objects.exists() and not force:
            self.stdout.write("Баннеры: уже есть, не трогаю")
            return
        for sort, (title, tag, filename, link_type, link_value) in enumerate(BANNERS):
            banner, _ = Banner.objects.update_or_create(
                title=title,
                defaults={
                    "tag": tag,
                    "link_type": link_type,
                    "link_value": link_value,
                    "sort_order": sort,
                    "is_active": True,
                },
            )
            self._save(banner.image, filename, f"banner{banner.id}")
        self.stdout.write(f"Баннеры: {len(BANNERS)}")

    def _own_shop(self):
        """Бейдж «Наш магазин» — демо-отметка первого магазина (снимается в админке)."""
        if Shop.objects.filter(is_own=True).exists():
            return
        shop = Shop.objects.order_by("id").first()
        if shop is None:
            return
        shop.is_own = True
        shop.save(update_fields=["is_own", "updated_at"])
        self.stdout.write(f"«Наш магазин»: {shop.name}")
