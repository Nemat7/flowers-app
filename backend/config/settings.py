"""
Настройки проекта Flowers & Sweets.

Все параметры окружения — через переменные (см. .env.example):
DATABASE_URL (postgis://...), REDIS_URL, DEBUG, SECRET_KEY, ALLOWED_HOSTS,
CORS_ALLOWED_ORIGINS, CSRF_TRUSTED_ORIGINS.
"""
from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env(
    DEBUG=(bool, False),
)
env_file = BASE_DIR / ".env"
if env_file.exists():
    environ.Env.read_env(env_file)

SECRET_KEY = env("SECRET_KEY", default="insecure-dev-key-change-me")
DEBUG = env("DEBUG")
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=["*"] if DEBUG else [])

# За TLS-проксёй (Railway и т.п.): доверяем X-Forwarded-Proto, чтобы Django видел https,
# иначе CSRF отклоняет POST из браузера (логин в админку и т.п.).
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
# HTTPS-origins, которым разрешены POST (админка, формы). Пример: https://api.example.com
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])

INSTALLED_APPS = [
    "daphne",  # ASGI-сервер для runserver (WebSocket, api.md §7)
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.gis",
    # third-party
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "drf_spectacular",
    "channels",
    "corsheaders",
    # local apps
    "accounts",
    "core",
    "catalog",
    "orders",
    "payments",
    "delivery",
    "reviews",
    "marketing",
    "disputes",
    "notifications",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",  # раздача staticfiles в проде без nginx
    "corsheaders.middleware.CorsMiddleware",  # до CommonMiddleware — для Flutter web dev-сервера
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

# --- БД: PostgreSQL + PostGIS ---
DATABASES = {
    "default": env.db_url(
        "DATABASE_URL",
        default="postgis://postgres:postgres@localhost:5432/flowers",
    )
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

AUTH_USER_MODEL = "accounts.User"

# --- Redis: кэш (rate limit OTP), Celery broker, channel layer ---
REDIS_URL = env("REDIS_URL", default="redis://localhost:6379/0")

CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": REDIS_URL,
        "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},
    }
}

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [REDIS_URL]},
    }
}

CELERY_BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
CELERY_TIMEZONE = "Asia/Dushanbe"

# --- Локализация ---
LANGUAGE_CODE = "ru"
TIME_ZONE = "Asia/Dushanbe"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"

# --- DRF ---
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 20,
    "EXCEPTION_HANDLER": "core.exceptions.flowers_exception_handler",
}

# --- JWT (api.md: access 30 мин / refresh 30 дней, rotation) ---
from datetime import timedelta  # noqa: E402

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=30),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=30),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
}

SPECTACULAR_SETTINGS = {
    "TITLE": "Flowers & Sweets API",
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
}

# --- OTP ---
OTP_CODE_TTL_SECONDS = 5 * 60  # TTL 5 минут
OTP_MAX_ATTEMPTS = 5
OTP_RESEND_INTERVAL_SECONDS = 60  # не чаще 1 SMS / 60 сек
OTP_DAILY_LIMIT = env.int("OTP_DAILY_LIMIT", default=100 if DEBUG else 5)  # не более N SMS / сутки (в dev послабление)

# --- SMS (accounts/sms.py) ---
# "console" — печать в лог (dev), "osonsms" — шлюз osonsms.com (ждём API-документацию).
SMS_BACKEND = env("SMS_BACKEND", default="osonsms" if not DEBUG else "console")
OSONSMS_API_URL = env("OSONSMS_API_URL", default="")
OSONSMS_LOGIN = env("OSONSMS_LOGIN", default="")
OSONSMS_HASH = env("OSONSMS_HASH", default="")
OSONSMS_SENDER = env("OSONSMS_SENDER", default="")

# --- Заказы: правила отмен (business-logic.md §7, docs/refund-policy.md) ---
# Удержание при отмене клиентом: магазин принял/собирает (accepted, preparing), %.
CANCEL_RETENTION_PREPARING_PERCENT = env.float(
    "CANCEL_RETENTION_PREPARING_PERCENT", default=10.0
)
# Удержание при отмене клиентом: букет собран/курьер назначен (ready, courier_assigned), %.
CANCEL_RETENTION_READY_PERCENT = env.float("CANCEL_RETENTION_READY_PERCENT", default=20.0)

# --- Платежи ---
# stub-провайдер разрешён только в DEBUG/staging; в проде выключен.
ALLOW_STUB_PAYMENTS = env.bool("ALLOW_STUB_PAYMENTS", default=DEBUG)

# --- CORS ---
# Нужен для Flutter web dev-сервера (Chrome-превью ходит на API с другого origin).
# В проде задать CORS_ALLOWED_ORIGINS явно (домены панели магазина).
from corsheaders.defaults import default_headers

CORS_ALLOW_HEADERS = (*default_headers, "idempotency-key")

if DEBUG:
    CORS_ALLOW_ALL_ORIGINS = True
else:
    CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS", default=[])
