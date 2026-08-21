# Прогресс проекта — что сделано и как проверено

Дата среза: 18.08.2026. Статусы: ✅ проверено вживую / 🧩 каркас готов, логика — следующий этап.

---

## 1. Проектные документы (docs/)

| Документ | Содержание | Статус |
|---|---|---|
| `docs/business-logic.md` | Роли (клиент/магазин/курьер/админ/саппорт), сценарий заказа, машина статусов, приём заказов магазином, админка, своя доставка с первого дня, эскроу и возвраты, монетизация, стек, roadmap, план выхода на рынок с нуля | ✅ утверждён |
| `docs/db-schema.md` | 25 моделей по 10 Django-apps, типы полей, индексы, 8 инвариантов (один магазин на заказ, снимки цен, начисление только при completed и т.д.) | ✅ утверждено |
| `docs/api.md` | ~60 REST endpoints по ролям + 3 WebSocket-канала, конвенции (JWT, пагинация, формат ошибок, идемпотентность), сводная таблица переходов статусов | ✅ утверждено |

Ключевые принятые решения: доставка своя (на старте — основатели); стек Flutter + React + Django/DRF/Channels + PostgreSQL/PostGIS + Redis + Celery; SMS — osonsms.com (API-документацию предоставит провайдер); платежи — Алиф + Душанбе Сити (договоры в процессе, разработка на stub-провайдере).

---

## 2. Backend-скаффолд (backend/)

- Django 5-проект `config` + 10 apps: accounts, catalog, orders, payments, delivery, reviews, marketing, disputes, notifications, core.
- Все 25 моделей по схеме, включая PostGIS-поля, enum'ы через TextChoices, индексы, unique-ограничения, partial unique «один успешный платёж на заказ».
- Кастомный User (логин по телефону), OTP (HMAC-хэш кода, TTL 5 мин, 5 попыток, rate limit 1/60 сек и 5/сутки).
- `orders/state_machine.py` — таблица допустимых переходов + валидация.
- Django Admin: все модели; аудит/история/ledger — readonly.
- Инфраструктура: Dockerfile (python:3.12 + GDAL), docker-compose (PostGIS 16, Redis 7, backend, celery), .env.example, README.
- Отступление от схемы: добавлено `Order.idempotency_key` (миграция orders/0002) — требование спеки об идемпотентном создании заказа.

**Проверки скаффолда (в Docker):** `manage.py check` — 0 ошибок; миграции применены к живому PostGIS; суперюзер создан; smoke-тест auth-цепочки (OTP → JWT → users/me → refresh); 429 на повторный OTP; `/admin/` и `/api/schema/` отвечают; Celery подключился к Redis. Машина статусов — 22 тест-кейса (включая запрет отмены после picked_up), все зелёные.

---

## 3. API каталога и заказов

**Каталог:** `GET /categories/`, `GET /shops/` (гео-сортировка по PostGIS-distance при lat/lng, фильтры open_now/q, скрытие is_hidden), `GET /shops/{id}/`, `GET /products/` (фильтры), `GET /products/{id}/`. `is_open` из рабочих часов в TZ Asia/Dushanbe, поддержка ночных смен.

**Заказы клиента:**
- `POST /orders/` — все проверки: один магазин, наличие, approved, asap→открыт/scheduled→часы, точка внутри зоны (PostGIS contains), min_order, промокод; серверный расчёт subtotal/delivery_fee (база + за км)/discount/total; снимки цен; номер F-XXXXXX; PIN доставки; идемпотентность по Idempotency-Key; Celery-таймаут оплаты 15 мин.
- `GET /orders/`, `GET /orders/{id}/`, `POST /orders/{id}/cancel/` (полный возврат до accepted; −10% до выезда курьера; 409 после), `POST /orders/{id}/review/` (обновление рейтинга магазина).

**Заказы магазина:** `GET /shop/orders/` (pending/active/history), `GET /shop/orders/{id}/` (телефон получателя скрыт до accepted), `accept` (с ETA), `reject` (причина + авто-возврат), `ready`. Скоуп по ShopStaff, чужой магазин → 404.

**Платежи:** BasePaymentProvider + StubPaymentProvider + фабрика (место под Алиф/DC); `POST /orders/{id}/pay/` с идемпотентностью; stub только в DEBUG/staging.

**Celery (реальные, идемпотентные):** `expire_unpaid_order` (15 мин), `shop_response_timeout` (5 мин → авто-возврат + штрафной счётчик, 3 подряд → магазин скрыт из выдачи), `complete_delivered_order` (2 ч → completed + начисление в ledger).

**Прочее:** единый формат ошибок `{error:{code,message,details}}`; SMS-бэкенды (Console default, OsonSMS — TODO по документации провайдера); `seed_demo` (2 магазина в центре Душанбе, 7 товаров, зона-полигон, промокод, тестовые клиент и сотрудник магазина).

### Тесты и результаты

**43 автотеста** (`orders/tests.py`, Django TestCase + DRF APIClient) — **все зелёные** (свежий прогон 04.08.2026: `Ran 43 tests … OK`, ~2.3 сек):

- создание заказа: успех + каждая валидация (товары разных магазинов, недоступен, магазин закрыт, вне зоны, min_order, промокод невалиден/просрочен/лимиты);
- расчёт сумм (530 + 10 − 53 = 487 — сходится);
- идемпотентность создания заказа и оплаты (повтор → тот же объект, без дублей);
- отмена: все ветки (полный возврат / −10% / 409 после picked_up);
- accept/reject/ready магазином, сокрытие телефона получателя;
- доступ: 404 чужому магазину, 403 клиенту в панели магазина;
- гонки Celery-таймаутов (task при уже изменённом статусе — корректный no-op);
- 3 таймаута подряд → магазин is_hidden и исчезает из выдачи;
- денормализация рейтинга магазина после отзыва.

**E2E-прогон в живом Docker-контейнере** (скрипт по HTTP): OTP-вход клиента → список магазинов с координатами → создание заказа (F-300064, total 492.77; идемпотентный повтор → тот же id) → stub-оплата (повтор → тот же платёж) → OTP-вход сотрудника → pending-лист (телефон скрыт) → accept(25 мин) → ready (телефон виден) → второй заказ → оплата → отмена → **Refund 492.77 success, payment → refunded** (проверено в БД). Celery-воркер реально получает задачи.

---

## 4. API курьера и WebSocket-трекинг (api.md §6, §7)

**API курьера** (`delivery/`): `PATCH /courier/status/` (offline запрещён при активном заказе — 409 active_delivery), `GET /courier/orders/current/`, `GET /courier/orders/available/` (ready без курьера, с distance), `POST …/accept/` (гонка двух курьеров → второму 409 order_taken через select_for_update; не-online → 400 courier_offline; с активным заказом → 409 active_delivery), `pickup` (picked_up→on_the_way, старт трекинга), `arrive`, `complete` (PIN → 400 invalid_pin при неверном; или фото multipart → delivered; планируется `complete_delivered_order` через 2 ч; курьер снова online), `POST /courier/location/` (батч точек; живые — в Redis `courier:loc:{id}` TTL 60 сек; в CourierLocation прорежено 1 точка/20 сек через атомарный cache.add; только при доставке picked_up..arrived), `GET /courier/earnings/` (today/week/total по Delivery.fee за delivered+completed), `GET /courier/orders/history/`. Права — `IsCourier` (наличие CourierProfile); чужой заказ курьеру → 404. Все переходы — через state_machine + OrderStatusHistory.

**WebSocket** (реальный, эхо-заглушка убрана): `/ws/client/orders/{id}/` (только владелец: status_changed, courier_location), `/ws/shop/` (сотрудник: new_order при оплате с expires_at, order_cancelled), `/ws/courier/` (order_available с distance от позиции курьера — персональный канал courier_{user_id}; order_taken — группа couriers_online, вход/выход по PATCH status через служебное set_online). Отправка инкапсулирована в `core/ws_events.py`, вызывается из всех переходов (оплата, accept/reject/ready магазина, отмена клиентом, Celery-таймауты, курьерские переходы). Push — `core/push.py::send_push` заглушка с TODO (логирует) во всех тех же местах. Добавлен `daphne` в requirements и INSTALLED_APPS (ASGI для runserver/WS).

**seed_demo:** курьер +992900000003 (online, позиция в центре).

### Тесты и результаты

**82 автотеста — все зелёные** (прогон 07.08.2026: `Ran 82 tests … OK`, ~9 сек): 43 прежних (регрессия чистая) + 29 курьерских (`delivery/tests.py`: линия, accept с гонкой/проверками, pickup/arrive/complete с PIN и фото, права, прореживание трека + Redis, earnings/history) + 10 WS (`core/test_ws.py`, WebsocketCommunicator + InMemoryChannelLayer: auth 4401/4403, status_changed, new_order при оплате через API, order_available с distance, order_taken, courier_location).

**E2E в живом Docker:** `backend/scripts/e2e_courier_flow.py` (REST: OTP → заказ → оплата → accept/ready → курьер online → available → accept → pickup → location → arrive → complete(pin, включая 400 на неверный PIN) → delivered → earnings=+fee → полная история статусов) и `backend/scripts/e2e_ws_flow.py` (реальный WS-клиент на websockets внутри контейнера: все 3 канала, new_order/order_available/order_taken/status_changed/courier_location по живому Redis channel layer). Оба — PASS.

---

## 5. Макеты интерфейса (mockups/client/)

- 6 hi-fi экранов клиентского приложения (390×844, iPhone): главная, витрина магазина, карточка товара, оформление (адрес/получатель/открытка/слот), оплата (Алиф/DC), отслеживание (карта, LIVE-статус, PIN).
- **Актуальная версия макетов — `mockups/client/v5/`** (9 экранов + PNG-рендеры: главная, магазин, товар, заказы, профиль, корзина, оформление, оплата, отслеживание). Версии v1/v2 в корне `mockups/client/`, промежуточные — в `v3/`, `v4/`.
- Дизайн-система v1–v2: белый фон, акцент #D6336C, вторичный #5B8C5A. **С v5 сменилась**: белый фон, зелёный акцент #06C167 точечно, CTA — чёрные пилюли, текст #191919/#757575, заливки #F6F6F6, обводки #EFEFEF, Inter 400–800. Реализована в `app/lib/src/theme/colors.dart`.
- Реальные фото (Wikimedia Commons/Flickr, свободные лицензии) — локально в `img/`; рендеры в `png/` (2x) + обзорный `overview.png`.
- Проверено визуально: каждый экран прочитан с рендера, найденные дефекты (z-index CTA, обрезка итогов, подписи карты) исправлены.
- **Главная переработана по запросу заказчика: shop-first** (`01-home-v2.html` / `png/01-home-v2.png`) — крупные карточки магазинов как главный вход (бейдж «Открыто/Закрыто», рейтинг, время, мин. заказ, промо-плашка), адрес сверху, поиск, чипы-фильтры. **Согласовано заказчиком.**

---

## 6. Клиентское приложение (app/, Flutter 3.44.9) — ✅ готово, проверено вживую в Chrome

**Инфраструктура приложения:** feature-first структура `lib/src/`; Material 3-тема по дизайн-системе; Dio API-клиент (JWT Bearer + авто-refresh по 401 с дедупом параллельных refresh, разбор ошибок спеки); provider; токены в shared_preferences; форматтеры сомони. Backend подготовлен к web-превью: django-cors-headers (+ `idempotency-key` в CORS_ALLOW_HEADERS — найдено при живом тесте).

**Экраны и логика:**
- Вход по OTP (+992 маска, 6 цифр, dev-код подсказкой в DEBUG, resend-таймер). Исправлен навигационный баг: после успешного verify экраны логина снимаются со стека (popUntil first) — раньше главная открывалась только по «назад».
- Главная shop-first (по макету v2): адрес, поиск (визуально), чипы, карточки магазинов из `GET /shops/?lat&lng`, pull-to-refresh, состояния загрузки/ошибки/пусто.
- Витрина магазина: шапка, чипы категорий с фильтром, сетка товаров, пилюля «Корзина · X с.».
- Карточка товара: hero, состав, кросс-сейл «Добавьте сладости», +/- количество.
- Корзина (provider): правило **один магазин на заказ** — диалог «Очистить корзину?» при товаре другого магазина.
- Оформление: пресет адреса (TODO геолокация), слот asap/scheduled, получатель, анонимность, открытка 0/300, промокод, валидация; Idempotency-Key стабилен между тапами (uuid, пакет uuid).
- Оплата: таймер резерва 15:00, Алиф/DC → stub-провайдер (подпись «тестовый режим»), карта disabled; экран «Заказ оплачен».
- Заказы: вкладки Активные/История; **перезагрузка списка при каждом открытии вкладки** (баг «заказ не виден до перезахода» — исправлен, GlobalKey + reload()).
- Детали заказа: статус-блок с LIVE-бейджем, стилизованная карта (CustomPainter, реальные координаты, анимированный маркер курьера; TODO 2GIS/Google на нативных сборках), таймлайн, карточка курьера с «Позвонить» (url_launcher), PIN в квадратиках, **отмена заказа** с диалогом (полный возврат / «минус 10%» по стадии).
- Трекинг: `tracking_service.dart` — WS /ws/client/orders/{id}/ с backoff-reconnect (1→2→5→15 сек), refresh токена перед reconnect, после 3 неудач — polling 10 сек (UI не замечает разницы); остановка при финальном статусе/dispose.

**Backend-дополнения под приложение (10.08):** `OrderDetailSerializer` отдаёт `shop_location` и `courier {name, phone}` (проверено живьём на заказе №10); OTP: новый код инвалидирует старые, `OTP_DAILY_LIMIT` в DEBUG = 100 (было 5 — блокировало тестирование, нашёл заказчик).

**Проверки:** `flutter analyze` — 0 ошибок; **37/37 тестов зелёные** (корзина, модели заказа, idempotency, auth-gate, WS-парсер/reconnect/fallback); `flutter build web` — успешно; живой прогон заказчиком в Chrome: вход, каталог, заказ, оплата stub, отмена, список заказов — **подтверждено работающим**. Запуск: `cd app && flutter run -d chrome --web-port=8080` (backend: `cd backend && docker compose up -d`).

---

## 7. Курьерский режим (в том же приложении, app/) — ✅ готов, E2E пройден

Решение: не отдельное приложение, а ветвление по роли — после OTP `user.role == "courier"` → CourierShell вместо клиентского MainShell (AuthGate). Экономия: переиспользованы тема, API-клиент, auth.

- **API**: +10 courier-методов в ApiClient (status/current/available/accept/pickup/arrive/complete/location/earnings/history), модели по фактическим JSON (проверены curl: available — plain list, decimal-строки, `busy` возвращается при активном заказе).
- **Экран «Заказы»** (минимум тапов): большой тогл «На линии» (offline при активном заказе — ошибка сервера), доступные заказы (WS `order_available` → перечитка списка + polling 15 сек fallback; `order_taken` → карточка убирается; гонка 409 → snackbar), активный заказ-шагер: магазин → «Забрал заказ» → получатель + звонок `tel:` → «Я на месте» → PIN (4–6 цифр, invalid_pin не ломает состояние) → «Завершить». Кнопка «Маршрут» — Google Maps по координатам.
- **GPS**: `LocationTracker` — буфер → батч каждые 10 сек на POST /courier/location/ (при ошибке точки возвращаются в буфер, stop досылает); пакет geolocator, отказ разрешения не блокирует шаги. Отправка только пока picked_up..arrived.
- **WS** `courier_ws.dart` — /ws/courier/ с backoff-reconnect и refresh токена (по образцу tracking_service).
- **«Заработок»**: today/week/total + история доставок (первая страница, догрузки нет).

**Проверки:** analyze — 0 ошибок; **62/62 тестов** (37 клиентских + 25 курьерских: модели, стейт-машина шагов, LocationTracker, WS); build web — успешно; живой E2E (`e2e_courier_flow.py`): online → available → accept → pickup → location → arrive → неверный PIN (400) → complete — PASS.

**Известные мелочи:** PIN 4-значный (backend генерирует 04d); нет GET /courier/status/ — после перезапуска тогл показывает offline до первого тача (busy восстанавливается по current); фото-подтверждение не делалось.

---

## 8. Панель магазина (shop-panel/, React + TS + Vite) — ✅ готова (блок заказов)

- **Стек**: Vite + React + TS, react-router v6, plain fetch-обёртка (Bearer + авто-refresh single-flight по 401), context/hooks, plain CSS в палитре проекта. Адаптив от 768px (планшет магазина). Порт dev: 5173.
- **Вход**: OTP (dev_code-подсказка в DEV), проверка роли shop_staff, экран «Нет доступа» для остальных. Тестовый сотрудник: +992900000002.
- **Входящие заказы**: WS /ws/shop/ (new_order → карточка + **звук WebAudio** (beep-арпеджио, unlock по первому клику) + мигание), таймер обратного отсчёта (точный из WS expires_at; для REST-заказов оценочный created_at+6 мин — backend не отдаёт expires_at в списке), состав, текст открытки крупно, слот, сумма; «Принять» с ETA-чипами 15/20/30/45, «Отклонить» с обязательной причиной (быстрые причины + поле). Polling fallback 15 сек.
- **В работе / История**: «Заказ готов» (ready); адрес/телефон получателя после принятия (backend скрывает телефон до accept — null обрабатывается).
- **Товары и часы работы** (12.08): backend `/shop/products/` (CRUD, toggle-available, фото) и `/shop/hours/` + разделы «Товары» и «Часы работы» в панели. Магазин ведёт каталог сам.
- **Финансы** (18.08): раздел «Финансы» в панели — см. §9а.

**Проверки:** tsc + vite build — 0 ошибок; dev-сервер 200; сквозной прогон curl: заказ клиентом (201) → stub-оплата (201) → появился в pending → accept eta=20 (200, телефон открылся) → ready (200); reject без причины → 400 validation_error, с причиной → 200.

---

## 9. Главный экран и карточка товара по макетам v5 (13.08) — ✅ проверено в браузере

Приведение фронта к `mockups/client/v5`: главная и карточка товара расходились с макетом, остальные экраны заказчик принял.

**Backend (под блоки главной):** `Shop.cover_photo` в выдаче + `Shop.is_own` («Наш магазин»), `Category.image`, `Product.is_featured` («Наше фирменное» / «Наш бренд»), `Banner.tag`; вычисляемые поля карточки `kind` (профиль магазина по категории его товаров, Subquery) и `delivery_fee_from` (мин. база по зонам); фильтр `GET /products/?featured=1`; **новый `GET /banners/`** (был в спеке, не был реализован). Миграции `catalog/0003`, `marketing/0003`. Флаги `is_own`/`is_featured` редактируются прямо в списках Django Admin.

**Команда `seed_media`** — демо-картинки для существующих данных (обложки, круги категорий, фото товарам без фото, 2 баннера, отметки «фирменное»), из `backend/demo_assets/`. Заполняет только пустые поля, магазинов не создаёт, `--force` перезаписывает. В отличие от `seed_demo`, безопасна на живой БД.

**Приложение:** главная переписана на единый `CustomScrollView` — скроллится целиком, как в макете (была прибитая шапка + скролл только списка). Добавлены карусель баннеров с точками-индикаторами (PageView 310/390), круги категорий, лента «Наше фирменное», ссылки «Все →». Карточка магазина: обложка 150px вместо логотипа в 16:9, бейдж «Наш магазин», мета «35–45 мин · Доставка от 10 с.» + профиль справа. Карточка товара: **исправлено перекрытие** — шит с radius 24 наезжал на фото, но в `CustomScrollView` фото красилось поверх и срезало заголовок (теперь Stack, шит рисуется вторым); подгружается `GET /products/{id}/` ради описания; кросс-сейл сужен до 158px по макету; убраны блок «Витрина →» и чип тега, которых в макете нет. Новые экраны-назначения `ProductListScreen` / `ShopListScreen` — чтобы «Все →» и категории не были мёртвыми кнопками.

**Проверки:** `flutter analyze` — 0 ошибок; **69/69 тестов** (62 прежних + 7 новых на парсинг полей карточки, баннера, категории и fallback описание→состав); **107/107 backend-тестов** (+5 на поля карточки, `featured=1`, `/banners/`, картинку категории); `flutter build web` — успешно; скриншоты главной и карточки товара сняты в headless Chrome (390×844) и сверены с рендерами макетов.

**Осознанные отличия от макета:** бейдж «Закрыто» + grayscale у закрытых магазинов — состояния нет в макете, но без него карточка врала бы о доступности; счётчик «1» на колокольчике не рисуется — endpoint'а уведомлений ещё нет.

---

## 9а. Финансы: backend + панель магазина + админ-дашборд (18.08) — ✅ готово

**Backend (payments/, core/):**
- `GET /shop/finance/summary/?from&to` — баланс (последний balance_after ledger) = «к выплате»; за период: начислено / комиссия / выплачено. По умолчанию текущий месяц.
- `GET /shop/finance/transactions/?from&to&page=` — ledger постранично (дата, тип, сумма ±, заказ №, баланс после).
- `GET /shop/finance/payouts/` — история выплат магазина.
- `GET /admin/dashboard/` (IsAdminUser) — заказы сегодня/месяц, GMV (неотменённые), **выручка платформы** (Σ commission_amount по completed), активные заказы по статусам, магазины approved/total, курьеры на линии, открытые споры, таймауты магазинов за день.

**Панель:** страница «Финансы» (в AppNav: Заказы/Товары/Часы/Финансы) — баланс крупно, 3 мини-карточки за месяц, фильтр периода ←/→, таблица транзакций (бейджи типов, ± цветом), пагинация, история выплат.

**Админ-дашборд:** `/admin/dashboard/` — HTML-страница в Django Admin (templates/admin/dashboard.html, ссылка «Дашборд» в шапке каждой страницы админки через base_site.html), карточки метрик без JS.

**Проверки:** тесты **122/122 зелёные** (+15: summary-арифметика, изоляция чужого магазина, пагинация, dashboard-агрегаты, 401/403). Живой прогон: сотрудник +992900000002 — summary 200 (balance 2069.75 = accrued 2435.00 − commission 365.25, сходится); админ dashboard 200; сквозное начисление по заказу F-300064 (535 с., комиссия 15% = 80.25 — ledger и дашборд сошлись). `npm run build` панели — успешно.

---

## 9б. SMS-интеграция OsonSMS (18.08) — ✅ реальные SMS работают

- Протокол провайдера получен (sms-api-documentation.pdf в корне проекта): GET api.osonsms.com/sendsms_v1.php, Bearer-токен, параметры from/phone_number(992XXXXXXXXX)/msg/login/txn_id; 201 = в очереди; дедуп по txn_id (409).
- `accounts/sms.py::OsonSMSBackend` реализован: Bearer из `OSONSMS_HASH`, `is_confidential=true` (коды не хранятся у провайдера), уникальный txn_id (uuid) на отправку, разбор ошибок провайдера в логи. Таймаут 20 сек по протоколу.
- Креды — в `backend/.env` (`OSONSMS_*`, `SMS_BACKEND=osonsms`); в git не попадают. В requirements добавлен `requests` (образ пересобирать при следующем build).
- **Проверено живьём:** check_balance.php → HTTP 200 (авторизация валидна, IP не в бане); OTP на реальный номер +992888887444 → SMS **получена** заказчиком. Тесты 122/122 не трогают реальный шлюз.
- ⚠️ У провайдера **белый список IP** (код 114): при деплое IP VPS добавить в whitelist в кабинете OsonSMS. Имя отправителя сейчас `OsonSMS` — фирменное имя запросить у провайдера.

---

## 10. Что ещё НЕ сделано

**Backend — остаток:** push через FCM (места вызовов расставлены, `core/push.py` — заглушка), webhooks Алиф/DC (stub-провайдер работает, ждём договоры и тестовый доступ банков), споры (модели есть, endpoints нет), `GET /payments/{id}/`, авто-назначение курьера (v1.2), `GET /orders/{id}/track/` REST-снимок, профиль магазина в панели (/shop/profile/).

**Приложение — остаток:** настоящая карта (2GIS/Google) вместо CustomPainter, геолокация/выбор адреса на карте, поиск (таб есть, экран-заглушка), профиль (адреса), избранное, догрузка страниц истории у курьера. Android-сборка настроена и проверена (см. §11); iOS — нужен Xcode, не ставился.

**Инфраструктура:** деплой на VPS (после — добавить IP VPS в whitelist OsonSMS), домен, SSL, CI/CD.

**Бизнес (параллельно, ведут основатели):** юрлицо, договоры Алиф/DC, первые 5–10 магазинов, фискализация.

---

## 11. Как поднять проект локально

```bash
cd backend && docker compose up -d                       # API :8002, PostGIS, Redis, Celery
cd backend && docker compose exec backend python manage.py seed_demo   # демо-данные (только на пустой БД)
cd backend && docker compose exec backend python manage.py seed_media  # картинки главной (безопасно на живой БД)
cd app && flutter run -d chrome --web-port=8080          # приложение :8080 (клиент + курьер по роли)
cd shop-panel && npm install && npm run dev              # панель магазина :5173
```

**APK на телефон** (13.08): адрес backend'а вынесен в `app/lib/src/api/config.dart` и задаётся при сборке — на устройстве `localhost` указывает на сам телефон. Телефон и ноутбук должны быть в одной Wi-Fi сети, IP смотреть через `ipconfig getifaddr en0`.

```bash
cd app && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=$HOME/Library/Android/sdk \
  flutter build apk --release --dart-define=SERVER_HOST=<ip-ноутбука>:8002
# → build/app/outputs/flutter-apk/app-release.apk (~53 МБ, подписан debug-ключом)
```

В манифест добавлены INTERNET, ACCESS_FINE/COARSE_LOCATION (GPS курьера), `usesCleartextTraffic` (http к локальному серверу — на проде убрать) и `queries` для url_launcher (звонок `tel:`, карты). JDK — Homebrew `openjdk@17`, Android Studio не требуется; `cmdline-tools` не установлены, но на сборку не влияют.

Тестовые аккаунты (OTP-код подсвечивается на экране в dev): клиент `+992900000001`, сотрудник магазина `+992900000002`, курьер `+992900000003`. Оплата — stub-провайдер (тестовый режим).
