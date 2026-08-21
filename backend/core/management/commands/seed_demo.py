"""seed_demo — демо-данные для ручного тестирования API (Душанбе, центр).

Создаёт: зону доставки «Центр», 2 магазина с часами работы, категории и
товары, промокод SPRING10, тестового клиента (+992900000001), сотрудника
магазина (+992900000002) и курьера (+992900000003, онлайн по умолчанию).
Идемпотентна (update_or_create).
"""
from datetime import time

import datetime

from django.contrib.gis.geos import Point, Polygon
from django.core.management.base import BaseCommand
from django.utils import timezone

from accounts.models import User
from catalog.models import Category, Product, Shop, ShopStaff, ShopWorkingHours
from core.models import DeliveryZone
from delivery.models import CourierProfile
from marketing.models import PromoCode

# центр Душанбе (пл. Дусти / Рудаки)
CENTER_LAT, CENTER_LNG = 38.5598, 68.7870

CLIENT_PHONE = "+992900000001"
STAFF_PHONE = "+992900000002"
COURIER_PHONE = "+992900000003"


class Command(BaseCommand):
    help = "Заполнить БД демо-данными для ручного тестирования"

    def handle(self, *args, **options):
        zone, _ = DeliveryZone.objects.update_or_create(
            name="Центр",
            defaults={
                # прямоугольник ~5×7 км вокруг центра Душанбе
                "polygon": Polygon(
                    (
                        (68.7400, 38.5300),
                        (68.8400, 38.5300),
                        (68.8400, 38.6000),
                        (68.7400, 38.6000),
                        (68.7400, 38.5300),
                    ),
                    srid=4326,
                ),
                "base_price": "10.00",
                "price_per_km": "2.00",
                "min_order_amount": "0.00",
                "is_active": True,
            },
        )

        shop1, _ = Shop.objects.update_or_create(
            name="Флора Душанбе",
            defaults={
                "description": "Цветы и букеты в центре Душанбе",
                "point": Point(CENTER_LNG, CENTER_LAT, srid=4326),
                "address_text": "пр. Рудаки 25",
                "phone": "+992900000100",
                "status": Shop.Status.APPROVED,
                "commission_rate": "15.00",
                "min_order_amount": "50.00",
                "card_price": "5.00",
            },
        )
        shop1.zones.set([zone])

        shop2, _ = Shop.objects.update_or_create(
            name="Сладкий Дом",
            defaults={
                "description": "Торты, капкейки и десерты",
                "point": Point(68.8050, 38.5750, srid=4326),
                "address_text": "ул. И. Сомони 14",
                "phone": "+992900000200",
                "status": Shop.Status.APPROVED,
                "commission_rate": "15.00",
                "min_order_amount": "30.00",
                "card_price": "0.00",
            },
        )
        shop2.zones.set([zone])

        for shop, (open_t, close_t) in (
            (shop1, (time(8, 0), time(22, 0))),
            (shop2, (time(9, 0), time(21, 0))),
        ):
            for weekday in range(7):
                ShopWorkingHours.objects.update_or_create(
                    shop=shop,
                    weekday=weekday,
                    defaults={
                        "open_time": open_t,
                        "close_time": close_t,
                        "is_day_off": False,
                    },
                )

        categories = {}
        for sort, (name, slug) in enumerate(
            [
                ("Букеты", "bukety"),
                ("Композиции", "kompozitsii"),
                ("Сладости", "sladosti"),
                ("Открытки", "otkrytki"),
            ]
        ):
            categories[slug], _ = Category.objects.update_or_create(
                slug=slug, defaults={"name": name, "sort_order": sort, "is_active": True}
            )

        products = [
            (shop1, "bukety", "Букет 15 красных роз", "350.00", "15 роз, эвкалипт, упаковка"),
            (shop1, "bukety", "Букет тюльпанов", "180.00", "21 тюльпан, крафт"),
            (shop1, "kompozitsii", "Композиция «Нежность»", "420.00", "розы, хризантемы, коробка"),
            (shop1, "otkrytki", "Открытка ручной работы", "10.00", ""),
            (shop2, "sladosti", "Торт «Медовик» 1 кг", "150.00", "мёд, сметанный крем"),
            (shop2, "sladosti", "Бенто-торт", "90.00", "ванильный бисквит, 400 г"),
            (shop2, "sladosti", "Капкейки ×6", "120.00", "ассорти: ваниль, шоколад"),
        ]
        for sort, (shop, cat_slug, name, price, composition) in enumerate(products):
            Product.objects.update_or_create(
                shop=shop,
                name=name,
                defaults={
                    "category": categories[cat_slug],
                    "price": price,
                    "composition": composition,
                    "is_available": True,
                    "is_active": True,
                    "sort_order": sort,
                },
            )

        PromoCode.objects.update_or_create(
            code="SPRING10",
            defaults={
                "type": PromoCode.Type.PERCENT,
                "value": "10.00",
                "min_order_amount": "100.00",
                "valid_from": datetime.datetime(2020, 1, 1, tzinfo=datetime.UTC),
                "valid_to": datetime.datetime(2030, 1, 1, tzinfo=datetime.UTC),
                "max_uses": None,
                "per_user_limit": 3,
                "is_active": True,
            },
        )

        client, _ = User.objects.update_or_create(
            phone=CLIENT_PHONE,
            defaults={"name": "Тестовый клиент", "role": User.Role.CLIENT},
        )
        staff, _ = User.objects.update_or_create(
            phone=STAFF_PHONE,
            defaults={"name": "Продавец Флоры", "role": User.Role.SHOP_STAFF},
        )
        ShopStaff.objects.get_or_create(
            user=staff, shop=shop1, defaults={"role": ShopStaff.Role.OWNER}
        )

        courier, _ = User.objects.update_or_create(
            phone=COURIER_PHONE,
            defaults={"name": "Тестовый курьер", "role": User.Role.COURIER},
        )
        CourierProfile.objects.update_or_create(
            user=courier,
            defaults={
                "status": CourierProfile.Status.ONLINE,  # онлайн по умолчанию
                "current_point": Point(CENTER_LNG, CENTER_LAT, srid=4326),
            },
        )

        self.stdout.write(
            self.style.SUCCESS(
                f"Готово: зона «{zone.name}», магазины «{shop1.name}» (#{shop1.id}), "
                f"«{shop2.name}» (#{shop2.id}), {len(products)} товаров, промокод SPRING10.\n"
                f"Клиент: {CLIENT_PHONE}, сотрудник магазина: {STAFF_PHONE}, "
                f"курьер: {COURIER_PHONE} (online) "
                f"(вход через OTP, в DEBUG код приходит в dev_code)."
            )
        )
