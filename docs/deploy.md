# Деплой Flowers & Sweets на production-VPS

Пошаговая инструкция: от свежекупленного VPS до работающего продакшена (~15 минут на сам деплой после готовности DNS).

**Архитектура стека** (`backend/docker-compose.prod.yml`, project name `flowers-prod`):

- `db` — PostGIS 16, без наружных портов (только внутренняя docker-сеть);
- `redis` — Redis 7 (кэш, Celery broker, channel layer), без наружных портов, AOF-persistence;
- `backend` — Django под **Daphne** (ASGI: HTTP + WebSocket), без наружного порта;
- `celery` — воркер фоновых задач (таймауты оплаты/ответа магазина/завершения заказа; event-driven, celery beat не нужен);
- `migrate`, `collectstatic`, `panel` — одноразовые сервисы (миграции, статика, сборка панели);
- `caddy` — единственная наружная точка (порты 80/443): автоматический HTTPS через Let's Encrypt, прокси на backend, раздача `/media/` и `/static/` из volumes, хостинг панели магазина на `panel.<DOMAIN>`.

---

## 0. Что нужно заранее

1. **VPS**: Ubuntu 24.04, минимум 2 vCPU / 2 ГБ RAM / 25 ГБ SSD. Должен быть открыт входящий трафик на порты 80 и 443 (Let's Encrypt не выдаст сертификат без этого).
2. **Домен** и две DNS A-записи на IP VPS:
   - `<DOMAIN>` → IP VPS (API, админка, медиа);
   - `panel.<DOMAIN>` → IP VPS (панель магазина).

   Проверка: `dig +short <DOMAIN>` и `dig +short panel.<DOMAIN>` должны вернуть IP сервера. **Сертификаты не выдадутся, пока DNS не указывает на VPS.**
3. **Доступ к репозиторию** с сервера (см. шаг 2).

## 1. Установка Docker на VPS

```bash
# на VPS под root (или через sudo)
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
docker compose version   # проверка: Docker Compose v2.x
```

## 2. Клонирование репозитория

Репозиторий: `git@github.com:Nemat7/flowers-app.git`.

Если репозиторий **публичный** — достаточно:

```bash
git clone https://github.com/Nemat7/flowers-app.git
cd flowers-app/backend
```

Если **приватный** — настроить deploy key (ключ только на чтение, только для этого репо):

```bash
# на VPS
ssh-keygen -t ed25519 -C "flowers-vps-deploy" -f ~/.ssh/flowers_deploy -N ""
cat ~/.ssh/flowers_deploy.pub
# Вставить ключ в GitHub: репозиторий → Settings → Deploy keys → Add deploy key (read-only)

cat >> ~/.ssh/config <<'EOF'
Host github.com
  IdentityFile ~/.ssh/flowers_deploy
EOF

git clone git@github.com:Nemat7/flowers-app.git
cd flowers-app/backend
```

## 3. Заполнение .env.production

```bash
cp .env.production.example .env.production
nano .env.production
```

Минимум, что нужно заполнить (остальное — см. комментарии в файле):

| Переменная | Что вписать |
|---|---|
| `DOMAIN` | ваш домен, например `flowers.tj` |
| `SECRET_KEY` | `python3 -c "import secrets; print(secrets.token_urlsafe(64))"` |
| `POSTGRES_PASSWORD` | `python3 -c "import secrets; print(secrets.token_urlsafe(24))"` |
| `DATABASE_URL` | тот же пароль: `postgis://postgres:<пароль>@db:5432/flowers` |
| `ALLOWED_HOSTS` | ваш домен (как `DOMAIN`) |
| `CORS_ALLOWED_ORIGINS` | `https://panel.<DOMAIN>` |
| `OSONSMS_LOGIN` / `OSONSMS_HASH` | креды OsonSMS (те же, что в dev `.env`) |

Проверить, что `DEBUG=False` и `ALLOW_STUB_PAYMENTS=False` — в проде stub-оплата должна быть выключена.

## 4. Сборка и запуск

```bash
cd flowers-app/backend
docker compose --env-file .env.production -f docker-compose.prod.yml build
docker compose --env-file .env.production -f docker-compose.prod.yml up -d
```

Что происходит при `up`:

1. поднимаются `db` и `redis` (ждут healthcheck);
2. `migrate` применяет миграции и завершается;
3. стартуют `backend` (Daphne) и `celery`;
4. `collectstatic` выкладывает статику в volume, `panel` собирает React-бандл в volume;
5. `caddy` запускается последним и **автоматически получает сертификаты Let's Encrypt** для `DOMAIN` и `panel.DOMAIN` (первая выдача — 10–30 секунд; смотреть `... logs -f caddy`).

Миграции и статика применяются автоматически при каждом `up` — отдельные команды не нужны.

## 5. Суперпользователь и первые данные

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml \
  exec backend python manage.py createsuperuser
```

- `seed_demo` — **НЕ запускать на проде**: создаёт тестовых клиентов/магазины/промокоды. Только для стенда.
- `seed_media` — можно при желании (безопасна: заполняет только пустые картинки у существующих данных), но на пустой БД делать нечего.
- Магазины, зоны доставки, категории, промокоды — заводить через админку `https://<DOMAIN>/admin/`.

## 6. Проверка

```bash
# API отвечает через HTTPS (401 — нормально: endpoint требует JWT)
curl -i https://<DOMAIN>/api/v1/categories/        # ожидаем HTTP 401

# админка и её статика
curl -I https://<DOMAIN>/admin/login/              # 200
curl -I https://<DOMAIN>/static/admin/css/base.css # 200

# панель магазина
curl -I https://panel.<DOMAIN>/                    # 200, отдаёт index.html
```

В браузере: открыть `https://panel.<DOMAIN>/`, войти сотрудником магазина (OTP придёт по SMS — см. шаг 7).

## 7. После первого запуска — OsonSMS whitelist

⚠️ **Обязательно:** у OsonSMS белый список IP-адресов. После появления VPS **добавить его IP в whitelist в кабинете OsonSMS** (иначе отправка SMS падает с кодом 114 и вход по OTP не работает).

Проверка после добавления IP: запросить OTP через `POST /api/v1/auth/otp/` на реальный номер — SMS должна прийти.

## 8. Чеклист первого запуска

- [ ] DNS: `dig +short <DOMAIN>` и `dig +short panel.<DOMAIN>` → IP VPS
- [ ] `.env.production` заполнен, `DEBUG=False`, `ALLOW_STUB_PAYMENTS=False`
- [ ] `docker compose ... ps` — все сервисы `Up (healthy)`, одноразовые — `Exited (0)`
- [ ] `curl https://<DOMAIN>/api/v1/categories/` → 401
- [ ] `https://<DOMAIN>/admin/` открывается по HTTPS, статика загружается
- [ ] `https://panel.<DOMAIN>/` открывается, вход по OTP работает (после whitelist OsonSMS)
- [ ] IP VPS добавлен в whitelist OsonSMS
- [ ] Создан суперпользователь; заведены категории, зоны доставки, магазины
- [ ] WebSocket: в панели магазина индикатор соединения активен (проверяется живым заказом)

## 9. Обновление (выкатка новой версии)

```bash
cd flowers-app/backend
git pull
docker compose --env-file .env.production -f docker-compose.prod.yml build
docker compose --env-file .env.production -f docker-compose.prod.yml up -d
```

Миграции, статика и бандл панели обновятся автоматически (сервисы `migrate`/`collectstatic`/`panel` отрабатывают при каждом `up`). Даунтайм — только на перезапуск контейнеров.

## 10. Логи и диагностика

```bash
cd flowers-app/backend
C="docker compose --env-file .env.production -f docker-compose.prod.yml"

$C ps                          # статус сервисов
$C logs -f backend             # API / Daphne (сюда же падают traceback'и)
$C logs -f celery              # фоновые задачи
$C logs -f caddy               # HTTPS, проксирование, ошибки сертификатов
$C logs --tail=100 db          # PostgreSQL
$C logs migrate                # результат миграций (одноразовый сервис)

# shell внутри backend (manage.py и т.п.)
$C exec backend python manage.py shell
```

Данные переживают пересоздание контейнеров — всё в volumes: `flowers-prod_pgdata` (БД), `flowers-prod_media` (загруженные файлы), `flowers-prod_staticfiles`, `flowers-prod_panel_dist`, `flowers-prod_caddy_data` (сертификаты), `flowers-prod_redisdata`.

## Приложение. Локальная проверка prod-стека

Прогонялось на машине разработчика 17.09.2026. Отличия от прода: `DOMAIN=localhost`, HTTP без TLS (`SITE_ADDRESS=http://localhost`), порты 8088/8443 (80/443 не трогаем — там может быть tajiflix), `SMS_BACKEND=console`. Стек поднимался с отдельным project name, dev-БД не затрагивалась. См. рецепт в `backend/.env.production.example` (переменные `HTTP_PORT`/`HTTPS_PORT`/`SITE_ADDRESS`/`PANEL_ADDRESS`).
