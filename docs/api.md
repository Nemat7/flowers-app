# API спецификация — Flowers & Sweets

REST API на Django REST Framework + WebSocket (Django Channels).

- Base URL: `https://api.<domain>/api/v1/`
- Аутентификация: JWT (access 30 мин / refresh 30 дней), header `Authorization: Bearer <access>`
- Логин — только OTP по телефону.
- Все даты — ISO 8601 UTC. Деньги — decimal в сомони.
- Пагинация списков: `?page=1&page_size=20`, ответ `{count, next, previous, results}`.
- Ошибки: `{ "error": { "code": "shop_closed", "message": "...", "details": {...} } }`,
  HTTP-коды: 400 валидация, 401/403 auth, 404, 409 конфликт состояния, 429 rate limit.
- Идемпотентность мутаций оплаты и создания заказа: header `Idempotency-Key: <uuid>`.

Роли: **client** (мобильное приложение), **shop** (веб-панель магазина),
**courier** (мобильное приложение), **admin** (Django Admin + несколько endpoint'ов
дашборда). Доступ к группам endpoint'ов проверяется по роли и владению объектом.

---

## 1. Auth и профиль (все роли)

| Метод | Endpoint | Описание |
|---|---|---|
| POST | `/auth/otp/request/` | `{phone}` → отправка SMS-кода. Rate limit: 1/60 сек, 5/сутки |
| POST | `/auth/otp/verify/` | `{phone, code}` → `{access, refresh, user}`; создаёт User при первом входе (роль client) |
| POST | `/auth/refresh/` | `{refresh}` → новая пара токенов (rotation) |
| POST | `/auth/logout/` | Инвалидация refresh + удаление Device |
| GET | `/users/me/` | Профиль текущего пользователя |
| PATCH | `/users/me/` | `{name}` |
| POST | `/users/me/devices/` | `{fcm_token, platform}` — регистрация push |
| GET | `/users/me/addresses/` | Список адресов клиента |
| POST | `/users/me/addresses/` | `{label, lat, lng, address_text, entrance?, floor?, apartment?, comment?, is_default?}` |
| PATCH/DELETE | `/users/me/addresses/{id}/` | Правка/удаление |
| GET | `/users/me/notifications/` | In-app лента уведомлений |
| POST | `/users/me/notifications/read/` | `{ids: [...]}` или `{all: true}` |

Вход сотрудника магазина и курьера — тот же OTP; роль назначается админом
(ShopStaff / CourierProfile), при verify возвращается `user.role`.

---

## 2. Каталог (client, публично с JWT)

| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/banners/` | Активные баннеры главного экрана: `{id, title, tag, image, link_type, link_value}`, без пагинации. `tag` — подпись над заголовком («Акция») |
| GET | `/categories/` | Категории каталога; `image` — круглая картинка для главной |
| GET | `/shops/` | `?lat&lng` → сортировка по расстоянию; поля: name, logo, cover_photo, is_own, rating, delivery_time_est, min_order, is_open, distance_m, kind, delivery_fee_from. Только `status=approved`. Фильтры: `?open_now=1`, `?q=` |
| GET | `/shops/{id}/` | Детали: часы работы, зоны, card_price, min_order, рейтинг |
| GET | `/products/` | Фильтры: `shop_id`, `category`, `q`, `price_min`, `price_max`, `tag`, `featured=1`, `available=1` (по умолчанию только доступные). Пагинация |
| GET | `/products/{id}/` | Карточка товара с фото, составом, магазином |

`is_open` считается из ShopWorkingHours + текущего времени (Asia/Dushanbe).

Поля карточки магазина на главной (макет v5 01-home): `cover_photo` — обложка
витрины (клиент падает на `logo`, если пусто); `is_own` — бейдж «Наш магазин»;
`kind` — профиль магазина по категории его товаров («Цветы»); `delivery_fee_from` —
минимальная база доставки по зонам магазина, точная сумма считается при заказе.
`featured=1` у товаров — лента «Наше фирменное» и бейдж «Наш бренд».

---

## 3. Заказы (client)

### POST `/orders/` — создание заказа
```json
{
  "shop_id": 12,
  "items": [{"product_id": 101, "qty": 1}, {"product_id": 205, "qty": 2}],
  "card_text": "С днём рождения, Гульчехра!",
  "is_anonymous": false,
  "recipient_name": "Гульчехра",
  "recipient_phone": "+992900000000",
  "address": {"lat": 38.5598, "lng": 68.7870, "address_text": "ул. Рудаки 25",
              "details": "подъезд 2, этаж 4, домофон 42"},
  "slot_type": "asap",                      // или "scheduled" + "scheduled_at"
  "promo_code": "SPRING10",                 // опционально
  "comment": "Позвонить за 10 минут"
}
```
Серверные проверки (при любой ошибке — 400/409 с кодом):
- все товары из одного магазина, `is_available`, магазин approved;
- для asap — магазин открыт; для scheduled — слот в рабочие часы;
- точка доставки ∈ одной из зон магазина, сумма ≥ min_order;
- промокод валиден (сроки, лимиты, min_order);
- расчёт `subtotal / delivery_fee / discount / total` — только на сервере.

Ответ 201: `{id, number, status: "created", total, payment: {...}}` — заказ ждёт оплаты,
TTL 15 минут (Celery: `expired`, слот и промокод освобождаются).

### Прочие endpoint'ы клиента
| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/orders/` | Мои заказы, `?status=active|history` |
| GET | `/orders/{id}/` | Детали: позиции, статус, история статусов, PIN доставки, суммы |
| POST | `/orders/{id}/cancel/` | Отмена клиентом. Не оплачен — свободно; до `accepted` — полный авто-возврат; `accepted`/`preparing` — возврат минус 10%; `ready`/`courier_assigned` — минус 20% (CANCEL_RETENTION_PREPARING/READY_PERCENT); после `picked_up` — 409, только через саппорт (docs/refund-policy.md) |
| POST | `/orders/{id}/photo/respond/` | `{approved: bool}` — реакция клиента на фото букета; один ответ на фото, магазину уходит WS `photo_approved`/`photo_rejected` |
| POST | `/orders/{id}/review/` | `{shop_rating, courier_rating?, text?}` — после `delivered` |
| POST | `/orders/{id}/dispute/` | `{reason, photos[]}` — открыть спор после `delivered` |
| GET | `/orders/{id}/track/` | REST-снимок: статус + последняя позиция курьера (живой трек — WS, §7) |

---

## 4. Платежи (client + webhooks)

| Метод | Endpoint | Описание |
|---|---|---|
| POST | `/orders/{id}/pay/` | `{provider: "alif"|"dc"}` + header `Idempotency-Key` → инициализация: `{payment_id, provider, deeplink|redirect_url, amount}`. Приложение открывает кошелёк провайдера |
| GET | `/payments/{id}/` | Статус платежа (клиент поллит после возврата из кошелька) |
| POST | `/payments/webhook/alif/` | Callback от Алиф. Проверка подписи, идемпотентность по provider_txn_id |
| POST | `/payments/webhook/dc/` | Callback от Душанбе Сити. Аналогично |

Логика webhook (критично):
1. Проверка подписи → 401 при невалидной.
2. Найти Payment по provider_txn_id / payment_id; если уже `success` → 200 (идемпотентно).
3. Сверить сумму с Order.total → расхождение = фрод-алерт админу, оплату не подтверждать.
4. Успех: Payment → `success`, Order → `paid` → `shop_pending`, push + WS магазину,
   запуск таймера принятия (Celery, 5–7 мин).
5. Возвраты: `POST /admin/payments/{id}/refund/` (только admin), статусы через тот же webhook.

До договоров с банками работает `provider: "stub"` — фиктивный успешный платёж
(только в DEBUG/staging, выключен в проде).

---

## 5. Панель магазина (shop)

JWT, роль shop_staff, скоуп — свой магазин (из ShopStaff). Каждый запрос
проверяет принадлежность объекта магазину.

### Заказы
| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/shop/orders/` | `?status=pending|active|history`, пагинация. pending = `shop_pending` (входящие); у pending-заказов есть `expires_at` — дедлайн принятия |
| GET | `/shop/orders/{id}/` | Карточка: состав, открытка, адрес, комментарий. `recipient_phone` скрыт до `accepted` |
| POST | `/shop/orders/{id}/accept/` | `{eta_minutes: 20}` → `accepted` (затем `preparing`), запуск ETA |
| POST | `/shop/orders/{id}/reject/` | `{reason}` (обязательно) → `rejected`, авто-возврат клиенту, клиенту push с предложением другого магазина |
| POST | `/shop/orders/{id}/ready/` | → `ready`, триггер назначения курьера |
| POST | `/shop/orders/{id}/photo/` | Фото собранного букета на одобрение клиенту: multipart `image`, только `accepted..ready`; клиенту — WS `bouquet_photo {photo_url}`, в деталях заказа — `bouquet_photo {url, approved}` |

Таймаут принятия: 5–7 мин (Celery). Не ответил → `timeout`, авто-возврат,
штрафной счётчик магазину; 3 подряд → авто-скрытие из выдачи + уведомление владельцу.

### Каталог магазина
| Метод | Endpoint | Описание |
|---|---|---|
| GET/POST | `/shop/products/` | Список / создание товара (фото — multipart) |
| PATCH/DELETE | `/shop/products/{id}/` | Правка; DELETE = `is_active=false` |
| POST | `/shop/products/{id}/toggle-available/` | Выключатель «в наличии» — один тап, без подтверждений |
| POST | `/shop/products/{id}/photos/` | Добавить фото; `DELETE .../photos/{photo_id}/` |

### Профиль и финансы
| Метод | Endpoint | Описание |
|---|---|---|
| GET/PATCH | `/shop/profile/` | Название, описание, фото, телефон; ИНН/юрданные — только чтение (меняет админ) |
| GET/PUT | `/shop/hours/` | Часы работы по дням недели |
| GET | `/shop/finance/summary/` | Баланс, начисления за период, комиссия |
| GET | `/shop/finance/transactions/` | Ledger (ShopBalanceTransaction), `?from&to` |
| GET | `/shop/finance/payouts/` | История выплат |

Новые заказы приходят в панель через WS `/ws/shop/` (§7) + звуковое оповещение на клиенте.

---

## 6. Курьер (courier)

JWT, роль courier. На старте курьеры — сами основатели: минимум тапов.

| Метод | Endpoint | Описание |
|---|---|---|
| GET/PATCH | `/courier/status/` | GET — текущий статус профиля; PATCH `{status: "online"|"offline"}` — выход на линию |
| GET | `/courier/orders/current/` | Текущий активный заказ (один заказ за раз в MVP) |
| GET | `/courier/orders/available/` | Заказы `ready` без курьера (если назначение не авто) |
| POST | `/courier/orders/{id}/accept/` | Взять заказ → `courier_assigned` |
| POST | `/courier/orders/{id}/pickup/` | Забрал у магазина → `picked_up` → `on_the_way`, старт трекинга |
| POST | `/courier/orders/{id}/arrive/` | На месте → `arrived`, клиенту push «курьер у двери» |
| POST | `/courier/orders/{id}/complete/` | `{pin}` или `{photo}` → `delivered` → (Celery, N ч без спора) → `completed`, начисление магазину |
| POST | `/courier/location/` | `{points: [{lat, lng, ts}]}` — батч GPS каждые 10–15 сек; живые позиции в Redis, прореженные — в CourierLocation |
| GET | `/courier/earnings/` | Заработок: сегодня/неделя, история |
| GET | `/courier/orders/history/` | Завершённые доставки |

Назначение в MVP: при `ready` заказ пушится всем онлайн-курьерам в зоне
(WS `/ws/courier/`), кто первый принял — тот везёт. Авто-назначение — v1.2.

---

## 7. WebSocket (Django Channels)

Auth: JWT в query (`?token=<access>`), проверка в middleware.

| Канал | Кто | События |
|---|---|---|
| `/ws/client/orders/{id}/` | Клиент (владелец заказа) | `status_changed {status, at}`; `courier_location {lat, lng}` каждые 5–10 сек пока `picked_up..arrived`; `bouquet_photo {photo_url}` — магазин прислал фото букета |
| `/ws/shop/` | Сотрудник магазина | `new_order {order_id, number, total, expires_at}`; `order_cancelled`; `photo_approved {order_id}` / `photo_rejected {order_id}` — реакция клиента на фото букета |
| `/ws/courier/` | Курьер онлайн | `order_available {order_id, shop, delivery_fee, distance}`; `order_taken` (заказ ушёл другому) |

Fallback для всех каналов — polling соответствующих REST endpoint'ов
(на случай нестабильной сети).

---

## 8. Админка

Основной интерфейс — **Django Admin** (магазины, пользователи, заказы, зоны,
промокоды, баннеры, выплаты, споры, аудит). Дополнительно REST для дашборда:

| Метод | Endpoint | Описание |
|---|---|---|
| GET | `/admin/dashboard/` | Заказы сегодня, GMV, выручка, активные магазины/курьеры, таймауты, открытые споры |
| GET | `/admin/orders/live/` | Живые заказы с координатами — карта в админке |
| POST | `/admin/orders/{id}/intervene/` | `{action: reassign_courier|force_status|cancel|refund, comment}` — каждое действие в AuditLog |
| POST | `/admin/shops/{id}/moderate/` | `{status: approved|rejected|suspended, comment}` |
| POST | `/admin/payments/{id}/refund/` | `{amount, reason}` — полный/частичный возврат |
| POST | `/admin/payouts/` | Создать выплату магазину/курьеру; `POST /admin/payouts/{id}/confirm/` — подтвердить |

---

## 9. Сводная таблица переходов статусов (кто что может)

| Переход | Инициатор | Endpoint / механизм |
|---|---|---|
| created → paid | система | webhook платежа |
| created → expired | система | Celery 15 мин |
| paid → shop_pending | система | автоматически после оплаты |
| shop_pending → accepted | магазин | `/shop/orders/{id}/accept/` |
| shop_pending → rejected | магазин | `/shop/orders/{id}/reject/` + авто-возврат |
| shop_pending → timeout | система | Celery 5–7 мин + авто-возврат |
| accepted → preparing | магазин | автоматически после accept |
| preparing → ready | магазин | `/shop/orders/{id}/ready/` |
| ready → courier_assigned | курьер | `/courier/orders/{id}/accept/` |
| courier_assigned → picked_up → on_the_way | курьер | `/courier/orders/{id}/pickup/` |
| on_the_way → arrived | курьер | `/courier/orders/{id}/arrive/` |
| arrived → delivered | курьер | `/courier/orders/{id}/complete/` (PIN/фото) |
| delivered → completed | система | Celery N ч без спора (старт: 2 ч) |
| …→ cancelled_client | клиент | `/orders/{id}/cancel/` (правила возврата §3) |
| …→ cancelled_admin | админ | `/admin/orders/{id}/intervene/` |
| delivered → disputed | клиент | `/orders/{id}/dispute/` |

Любой переход: запись в OrderStatusHistory + AuditLog, push клиенту,
WS-событие заинтересованным сторонам.
