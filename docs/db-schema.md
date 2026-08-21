# Схема БД — Flowers & Sweets

PostgreSQL + PostGIS. ORM — Django. Ниже — логические модели по Django-apps.
Соглашения: `id` — bigint PK (публичные идентификаторы заказов — отдельное поле
`number`), все даты — `timestamptz`, деньги — `decimal(10,2)` в сомони,
координаты — PostGIS `Point` (SRID 4326), мягкое удаление только где указано.

Apps: `accounts`, `catalog`, `orders`, `payments`, `delivery`, `reviews`,
`marketing`, `disputes`, `notifications`, `core` (аудит, зоны).

---

## 1. accounts — пользователи и аутентификация

### User
Кастомная модель, логин по телефону (OTP), без пароля.
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| phone | varchar(16) unique | формат +992XXXXXXXXX, E.164 |
| name | varchar(100) | |
| role | enum: client / shop_staff / courier / admin | базовая роль; права магазина — через ShopStaff |
| is_active | bool | блокировка |
| is_staff / is_superuser | bool | доступ в Django Admin |
| created_at, updated_at | timestamptz | |

Индексы: `phone` (unique).

### OTPCode
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| phone | varchar(16) | индекс |
| code_hash | varchar(128) | код не храним в открытом виде |
| expires_at | timestamptz | TTL 5 минут |
| attempts | smallint default 0 | max 5, далее код инвалидируется |
| is_used | bool | |

Rate limit: не чаще 1 SMS / 60 сек на номер, не более 5 / сутки (проверка через Redis).

### Address (сохранённые адреса клиента)
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| user | FK → User | индекс |
| label | varchar(50) | «Дом», «Работа» |
| point | geography(Point) | GIST-индекс |
| address_text | varchar(255) | улица, дом (снимок текстом) |
| entrance, floor, apartment | varchar(10) | подъезд/этаж/кв |
| comment | varchar(255) | «домофон 42» |
| is_default | bool | |

### Device (push-токены)
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| user | FK → User | |
| fcm_token | varchar(255) unique | |
| platform | enum: ios / android / web | |
| last_seen_at | timestamptz | для чистки мёртвых токенов |

---

## 2. core — зоны доставки и аудит

### DeliveryZone
Полигоны доставки платформы (доставка своя — зоны глобальные).
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| name | varchar(100) | «Центр», «Сино» |
| polygon | geography(Polygon) | GIST-индекс |
| base_price | decimal | базовая стоимость доставки |
| price_per_km | decimal | надбавка за км от магазина |
| min_order_amount | decimal | мин. сумма заказа в зону |
| is_active | bool | |

### AuditLog
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| actor | FK → User (null) | null = системное действие (Celery) |
| action | varchar(100) | order.status_changed, shop.blocked… |
| entity_type, entity_id | varchar(50), bigint | |
| before, after | jsonb | снимки до/после |
| created_at | timestamptz | индекс |

---

## 3. catalog — магазины и товары

### Shop
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| name | varchar(150) | |
| description | text | |
| inn | varchar(20) | ИНН юрлица/ИП |
| legal_name | varchar(200) | |
| phone | varchar(16) | |
| point | geography(Point) | GIST-индекс |
| address_text | varchar(255) | |
| logo, cover_photo | image | обложка витрины — картинка карточки на главной |
| is_own | bool | магазин платформы: бейдж «Наш магазин» |
| status | enum: pending / approved / rejected / suspended | индекс; в выдаче только approved |
| commission_rate | decimal(4,2) | % комиссии платформы, снимок в заказ |
| rating_avg | decimal(3,2) | денормализовано из Review |
| rating_count | int | |
| min_order_amount | decimal | |
| card_price | decimal | цена открытки, 0 = бесплатно |
| zones | M2M → DeliveryZone | куда магазин готов отправлять |
| created_at, updated_at | | |

### ShopWorkingHours
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| shop | FK → Shop | unique_together(shop, weekday) |
| weekday | smallint | 0=пн … 6=вс |
| open_time, close_time | time | |
| is_day_off | bool | |

### ShopStaff
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| user | FK → User | unique_together(user, shop) |
| shop | FK → Shop | индекс |
| role | enum: owner / manager | owner управляет персоналом и финансами |

### Category
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| name | varchar(100) | «Букеты», «Композиции», «Сладости», «Открытки», «Допы» |
| slug | varchar(100) unique | |
| icon | varchar(100) | |
| image | image | круглая картинка категории на главной |
| sort_order | int | |
| is_active | bool | |

### Product
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| shop | FK → Shop | индекс (shop, is_available, is_active) |
| category | FK → Category | |
| name | varchar(150) | |
| description | text | |
| composition | varchar(500) | «15 роз, эвкалипт, упаковка» |
| price | decimal | |
| is_available | bool | выключатель «в наличии» — критично, один тап |
| is_active | bool | скрыт магазином/модерацией |
| is_featured | bool | лента «Наше фирменное» + бейдж «Наш бренд» |
| tags | jsonb | повод/цвет: ["romantic","red"] |
| sort_order | int | |
| created_at, updated_at | | |

### ProductPhoto
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| product | FK → Product | |
| image | image | |
| sort_order | int | |

---

## 4. orders — заказы

### Order
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| number | varchar(12) unique | публичный №, напр. «F-004521» — генерируется, не последовательный id |
| client | FK → User | индекс |
| shop | FK → Shop | индекс (shop, status) |
| status | enum (см. машину статусов) | индекс (status) |
| **состав и открытка** | | |
| card_text | text | текст открытки, может быть пустым |
| card_price | decimal | снимок цены открытки |
| is_anonymous | bool | скрыть имя отправителя от получателя |
| **получатель** | | |
| recipient_name | varchar(100) | |
| recipient_phone | varchar(16) | |
| **адрес (снимок на момент заказа)** | | |
| delivery_point | geography(Point) | |
| delivery_address_text | varchar(255) | |
| delivery_details | varchar(255) | подъезд/этаж/комментарий одной строкой |
| **слот** | | |
| slot_type | enum: asap / scheduled | |
| scheduled_at | timestamptz null | для scheduled |
| **деньги (снимки)** | | |
| subtotal | decimal | сумма товаров + открытка |
| delivery_fee | decimal | |
| discount | decimal | по промокоду |
| total | decimal | subtotal + delivery_fee − discount |
| commission_rate | decimal(4,2) | снимок % магазина |
| commission_amount | decimal | рассчитывается при completed |
| promo_code | FK → PromoCode null | |
| comment | varchar(500) | комментарий клиента магазину |
| cancel_reason | varchar(255) | |
| created_at, updated_at | | |

Машина статусов (синхронизирована с business-logic.md §3):

```
created → payment_failed | expired | paid
paid → shop_pending → accepted | rejected | timeout
accepted → preparing → ready → courier_assigned → picked_up
picked_up → on_the_way → arrived → delivered → completed
любой до picked_up → cancelled_client | cancelled_shop | cancelled_admin
после delivered → disputed (через саппорт)
```

### OrderItem
Снимки — товар может измениться/удалиться после заказа.
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| order | FK → Order | индекс |
| product | FK → Product null | on_delete=SET_NULL |
| product_name | varchar(150) | снимок |
| price | decimal | снимок цены на момент заказа |
| qty | int | |
| photo_url | varchar(500) | снимок первого фото |

### OrderStatusHistory
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| order | FK → Order | индекс |
| status | enum | |
| changed_by | FK → User null | null = система |
| comment | varchar(255) | причина отклонения/отмены |
| created_at | timestamptz | |

### OrderPhoto (фото букета на одобрение, v1.1; таблица в MVP)
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| order | FK → Order | |
| image | image | |
| approved | bool null | null = ждёт реакции клиента |
| created_at | timestamptz | |

---

## 5. payments — платежи, возвраты, баланс

### Payment
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| order | FK → Order | индекс; один успешный на заказ (unique partial: provider_txn) |
| provider | enum: alif / dc / stub | stub — тестовый контур до договоров |
| amount | decimal | |
| status | enum: pending / success / failed / refunded / partially_refunded | |
| provider_txn_id | varchar(100) null | id транзакции у провайдера, индекс |
| idempotency_key | uuid unique | защита от двойной оплаты при ретраях клиента |
| raw_callback | jsonb | последний webhook провайдера — для разбора |
| created_at, updated_at | | |

### Refund
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| payment | FK → Payment | |
| amount | decimal | ≤ payment.amount − Σ refund |
| reason | varchar(255) | |
| status | enum: pending / success / failed | |
| provider_refund_id | varchar(100) null | |
| created_by | FK → User null | null = авто-возврат |
| created_at | timestamptz | |

### ShopBalanceTransaction (ledger магазина)
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| shop | FK → Shop | индекс |
| order | FK → Order null | |
| type | enum: accrual / commission / payout / adjustment | accrual +, commission −, payout −, adjustment ± |
| amount | decimal | со знаком |
| balance_after | decimal | для быстрой сверки |
| comment | varchar(255) | |
| created_at | timestamptz | |

Начисление происходит при `completed`: accrual(subtotal) + commission(−commission_amount).
Возврат клиенту до completed → accrual/commission не создаются (деньги на эскроу).

### Payout (выплата магазину или курьеру)
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| recipient_type | enum: shop / courier | |
| shop | FK → Shop null | |
| courier | FK → CourierProfile null | |
| amount | decimal | |
| method | enum: alif / dc / bank / cash | |
| status | enum: pending / paid / failed | в MVP подтверждается вручную админом |
| period_from, period_to | date | |
| confirmed_by | FK → User null | админ |
| created_at, paid_at | | |

---

## 6. delivery — курьеры и доставка

### CourierProfile
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| user | FK → User unique | role=courier |
| status | enum: offline / online / busy | индекс |
| current_point | geography(Point) null | последняя позиция, дублируется в Redis |
| rating_avg, rating_count | | |
| created_at | | |

### Delivery
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| order | FK → Order unique | 1:1 |
| courier | FK → CourierProfile null | null до назначения |
| fee | decimal | стоимость доставки курьеру (может отличаться от delivery_fee клиента) |
| pin_code | varchar(6) | код подтверждения получателя — показывается клиенту |
| confirmation_type | enum: pin / photo | |
| confirmation_photo | image null | |
| assigned_at, picked_up_at, arrived_at, delivered_at | timestamptz null | |
| created_at | | |

### CourierLocation (история трека)
Живые позиции — в Redis (гео-хэш, TTL). В БД пишем прореженный трек
(1 точка / 15–30 сек) для истории и споров.
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| delivery | FK → Delivery | индекс |
| point | geography(Point) | |
| recorded_at | timestamptz | |

---

## 7. reviews — отзывы

### Review
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| order | FK → Order unique | один отзыв на заказ |
| client | FK → User | |
| shop | FK → Shop | индекс; денормализация в Shop.rating_avg |
| shop_rating | smallint | 1–5 |
| courier_rating | smallint null | 1–5 |
| text | varchar(1000) | |
| created_at | timestamptz | |

---

## 8. marketing — промокоды и баннеры

### PromoCode
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| code | varchar(30) unique | регистронезависимый |
| type | enum: percent / fixed / free_delivery | |
| value | decimal | % или сумма |
| min_order_amount | decimal | |
| valid_from, valid_to | timestamptz | |
| max_uses | int null | null = безлимит |
| uses_count | int | |
| per_user_limit | int default 1 | |
| is_active | bool | |

### PromoCodeUse
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| promo_code | FK → PromoCode | unique_together(promo_code, order) |
| user | FK → User | индекс (promo_code, user) — per_user_limit |
| order | FK → Order | |

### Banner
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| title | varchar(150) | |
| tag | varchar(30) | подпись над заголовком: «Акция», «Доставка» |
| image | image | |
| link_type | enum: shop / category / promo / url | |
| link_value | varchar(255) | id или url |
| sort_order | int | |
| is_active | bool | |

---

## 9. disputes — споры

### Dispute
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| order | FK → Order | индекс |
| opened_by | FK → User | клиент |
| reason | varchar(500) | |
| photos | jsonb | список image url |
| status | enum: open / in_review / resolved_full_refund / resolved_partial_refund / resolved_rejected | |
| resolution_comment | varchar(500) | |
| refund_amount | decimal null | |
| resolved_by | FK → User null | саппорт/админ |
| created_at, resolved_at | | |

SLA: решение ≤ 24 ч (контроль через Celery-напоминание саппорту).

---

## 10. notifications — уведомления

### Notification
In-app лента уведомлений (push/SMS — транспорт, не хранится).
| Поле | Тип | Комментарий |
|---|---|---|
| id | bigint PK | |
| user | FK → User | индекс (user, is_read) |
| type | varchar(50) | order_status, promo, dispute… |
| title, body | varchar(255), varchar(500) | |
| data | jsonb | {order_id, status} — для deep link |
| is_read | bool | |
| created_at | timestamptz | |

---

## 11. Ключевые инварианты (проверки на уровне приложения)

1. Все позиции заказа — из одного магазина (проверка при создании).
2. `total = subtotal + delivery_fee − discount`, пересчёт только на сервере.
3. Цены в OrderItem — снимки; изменение Product.price не влияет на живые заказы.
4. Один успешный Payment на заказ; повторная оплата блокируется idempotency_key.
5. Переходы статусов — только по машине статусов (таблица допустимых переходов),
   каждый переход пишется в OrderStatusHistory + AuditLog.
6. Деньги магазину начисляются только при `completed`; при отмене/таймауте
   до `completed` — авто-возврат через Refund.
7. Заказ создаётся только если точка доставки ∈ зоне магазина и
   магазин approved + сейчас открыт (для asap).
8. PIN доставки генерируется при создании заказа, виден клиенту,
   получатель называет его курьеру (или фото).
