# Backend — Flowers & Sweets

Django 5 + DRF + Channels + Celery, PostgreSQL/PostGIS, Redis.
Спецификация: `../docs/db-schema.md`, `../docs/api.md`, `../docs/business-logic.md`.

## Быстрый старт (Docker)

```bash
cd backend
cp .env.example .env
docker compose build
docker compose up -d db redis
# Миграции — отдельной командой:
docker compose run --rm backend python manage.py migrate
# Суперюзер (телефон = логин):
docker compose run --rm \
  -e DJANGO_SUPERUSER_PHONE=+992900000000 \
  -e DJANGO_SUPERUSER_PASSWORD=admin123 \
  backend python manage.py createsuperuser --noinput
# Запуск:
docker compose up
```

- API: http://localhost:8000/api/v1/
- Админка: http://localhost:8000/admin/
- OpenAPI-схема: http://localhost:8000/api/schema/, Swagger UI: /api/docs/
- WebSocket (заглушка): `ws://localhost:8000/ws/?token=<access>`

Celery worker поднимается сервисом `celery` в compose.

## Auth (работает сейчас)

- `POST /api/v1/auth/otp/request/` `{phone}` — в DEBUG код возвращается в поле
  `dev_code` ответа и печатается в консоль (SMS — stub в `accounts/sms.py`).
- `POST /api/v1/auth/otp/verify/` `{phone, code}` → `{access, refresh, user}`.
- `POST /api/v1/auth/refresh/` `{refresh}` → новая пара (rotation).
- `GET/PATCH /api/v1/users/me/`.

## Структура

| Путь | Что там |
|---|---|
| `config/` | settings (env: DATABASE_URL, REDIS_URL, DEBUG, SECRET_KEY), urls, asgi (Channels), celery |
| `accounts/` | User (логин по phone), OTPCode, Address, Device; auth endpoints; `sms.py` (stub) |
| `core/` | DeliveryZone, AuditLog; WS middleware/consumer/routing |
| `catalog/` | Shop, ShopWorkingHours, ShopStaff, Category, Product, ProductPhoto |
| `orders/` | Order, OrderItem, OrderStatusHistory, OrderPhoto; `state_machine.py` (допустимые переходы), `tasks.py` (таймауты — заглушки) |
| `payments/` | Payment, Refund, ShopBalanceTransaction (ledger), Payout |
| `delivery/` | CourierProfile, Delivery, CourierLocation |
| `reviews/` | Review |
| `marketing/` | PromoCode, PromoCodeUse, Banner |
| `disputes/` | Dispute |
| `notifications/` | Notification (in-app лента) |

## Локальный запуск без Docker

Нужны PostgreSQL+PostGIS, Redis и системные GDAL/GEOS (macOS:
`brew install gdal postgis redis`). В `.env` хосты поменять на `localhost`.
Проверка без БД: `python manage.py check`.
